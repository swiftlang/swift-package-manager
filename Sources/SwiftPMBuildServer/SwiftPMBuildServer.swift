//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
#if canImport(LanguageServerProtocolTransport)
import Basics
import SwiftBuild
import Foundation
import SPMBuildCore
import SwiftBuildSupport
import SwiftBuild
import SWBBuildService
import Workspace
import BuildServerProtocol
import LanguageServerProtocol
import LanguageServerProtocolTransport
import ToolsProtocolsSwiftExtensions

// Remove these extensions once they've been added to swift-tools-protocols
package extension Connection {
    func withCancellableCheckedThrowingContinuation<Handle: Sendable, Result>(
        _ operation: (_ continuation: CheckedContinuation<Result, any Error>) -> Handle,
        cancel: @Sendable (Handle) -> Void
    ) async throws -> Result {
        let handleWrapper = ThreadSafeBox<Handle?>(nil)

        @Sendable
        func callCancel() {
            /// Take the request ID out of the box. This ensures that we only send the
            /// cancel notification once in case the `Task.isCancelled` and the
            /// `onCancel` check race.
            if let handle = handleWrapper.takeValue() {
                cancel(handle)
            }
        }

        return try await withTaskCancellationHandler(
            operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    handleWrapper.put(operation(continuation))

                    // Check if the task was cancelled. This ensures we send a
                    // CancelNotification even if the task gets cancelled after we register
                    // the cancellation handler but before we set the `requestID`.
                    if Task.isCancelled {
                        callCancel()
                    }
                }
            },
            onCancel: callCancel
        )
    }

    // Disfavor this over Connection.send implemented in swift-tools-protocols by https://github.com/swiftlang/swift-tools-protocols/pull/28
    // TODO: Remove this method once we have updated the swift-tools-protocols dependency to include #28
    @_disfavoredOverload
    func send<R: RequestType>(_ request: R) async throws -> R.Response {
        return try await withCancellableCheckedThrowingContinuation { continuation in
            return self.send(request) { result in
                continuation.resume(with: result)
            }
        } cancel: { requestID in
            self.send(CancelRequestNotification(id: requestID))
        }
    }
}

public actor SwiftPMBuildServer: QueueBasedMessageHandler {
    private let underlyingBuildServer: SWBBuildServer
    private let connectionToUnderlyingBuildServer: LocalConnection
    private let packageRoot: Basics.AbsolutePath
    private let buildSystem: SwiftBuildSystem
    private let workspace: Workspace

    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "build-server-message-handling",
        createLoggingScope: false
    )
    public let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()
    /// Serializes package loading
    private let packageLoadingQueue = AsyncQueue<Serial>()
    /// Connection used to send messages to the client of the build server.
    private let connectionToClient: any Connection

    /// Represents the lifetime of the build server implementation..
    enum ServerState: CustomStringConvertible {
        case waitingForInitializeRequest
        case waitingForInitializedNotification
        case running
        case shutdown

        var description: String {
            switch self {
            case .waitingForInitializeRequest:
                "waiting for initialization request"
            case .waitingForInitializedNotification:
                "waiting for initialization notification"
            case .running:
                "running"
            case .shutdown:
                "shutdown"
            }
        }
    }
    var state: ServerState = .waitingForInitializeRequest
    /// Allows customization of server exit behavior.
    var exitHandler: (Int) -> Void

    public init(packageRoot: Basics.AbsolutePath, buildSystem: SwiftBuildSystem, workspace: Workspace, connectionToClient: any Connection, exitHandler: @escaping (Int) -> Void) async throws {
        print("[DEBUG] SwiftPMBuildServer: Initializing...")
        self.packageRoot = packageRoot
        self.buildSystem = buildSystem
        self.workspace = workspace
        self.connectionToClient = connectionToClient
        self.exitHandler = exitHandler
        let session = try await buildSystem.createLongLivedSession(name: "swiftpm-build-server")
        let connectionToUnderlyingBuildServer = LocalConnection(receiverName: "underlying-swift-build-server")
        self.connectionToUnderlyingBuildServer = connectionToUnderlyingBuildServer
        let connectionFromUnderlyingBuildServer = LocalConnection(receiverName: "swiftpm-build-server")
        // TODO: fix derived data path, cleanup configured targets list computation
        let buildrequest = try await self.buildSystem.makeBuildRequest(
            session: session.session,
            configuredTargets: [.init(rawValue: "ALL-INCLUDING-TESTS")],
            derivedDataPath: self.buildSystem.buildParameters.buildPath,
            symbolGraphOptions: nil
        )
        print("[DEBUG] SwiftPMBuildServer: Creating underlying SWBBuildServer...")
        self.underlyingBuildServer = SWBBuildServer(
            session: session.session,
            containerPath: buildSystem.buildParameters.pifManifest.pathString,
            buildRequest: buildrequest,
            connectionToClient: connectionFromUnderlyingBuildServer,
            exitHandler: { exitCode in
                print("[DEBUG] SwiftPMBuildServer: exitHandler called with code \(exitCode)")
                // Tear down the session BEFORE closing the connection
                // The teardown may need the connection to be open for coordination
                do {
                    print("[DEBUG] SwiftPMBuildServer: Calling session.teardownHandler()...")
                    try await session.teardownHandler()
                    print("[DEBUG] SwiftPMBuildServer: session.teardownHandler() completed")
                } catch {
                    print("[ERROR] SwiftPMBuildServer: session.teardownHandler() failed: \(error)")
                }
                // Close the connection after teardown completes
                print("[DEBUG] SwiftPMBuildServer: Closing connection to underlying build server")
                connectionToUnderlyingBuildServer.close()
                print("[DEBUG] SwiftPMBuildServer: exitHandler completed")
            }
        )
        print("[DEBUG] SwiftPMBuildServer: Starting connections...")
        connectionToUnderlyingBuildServer.start(handler: underlyingBuildServer)
        connectionFromUnderlyingBuildServer.start(handler: self)
        print("[DEBUG] SwiftPMBuildServer: Initialization complete")
    }

    public func handle(notification: some NotificationType) async {
        switch notification {
        case is OnBuildExitNotification:
            print("[DEBUG] SwiftPMBuildServer: Received OnBuildExitNotification, state=\(state)")
            connectionToUnderlyingBuildServer.send(notification)
            if state == .shutdown {
                print("[DEBUG] SwiftPMBuildServer: State is shutdown, calling exitHandler(0)")
                exitHandler(0)
            } else {
                print("[DEBUG] SwiftPMBuildServer: State is \(state), calling exitHandler(1)")
                exitHandler(1)
            }
        case is OnBuildInitializedNotification:
            connectionToUnderlyingBuildServer.send(notification)
            state = .running
            scheduleRegeneratingBuildDescription()
        case let notification as OnWatchedFilesDidChangeNotification:
            // The underlying build server only receives updates via new PIF, so don't forward this notification.
            for change in notification.changes {
                if self.fileEventShouldTriggerPackageReload(event: change) {
                    scheduleRegeneratingBuildDescription()
                    return
                }
            }
        case is OnBuildLogMessageNotification:
            // If we receive a build log message notification, forward it on to the client
            connectionToClient.send(notification)
        case is OnBuildTargetDidChangeNotification:
            // If the underlying server notifies us of target updates, forward the notification to the client
            connectionToClient.send(notification)
        default:
            logToClient(.warning, "SwiftPM build server received unknown notification type: \(notification)")
        }
    }

    private func logToClient(_ kind: BuildServerProtocol.MessageType, _ message: String, _ structure: BuildServerProtocol.StructuredLogKind? = nil) {
        connectionToClient.send(
            OnBuildLogMessageNotification(type: .log, message: "\(message)", structure: structure)
        )
    }

    public func handle<Request: RequestType>(
        request: Request,
        id: RequestID,
        reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
    ) async {
        let request = RequestAndReply(request, reply: reply)
        switch request {
        case let request as RequestAndReply<BuildShutdownRequest>:
            await request.reply {
                print("[DEBUG] SwiftPMBuildServer: Handling shutdown request, sending to underlying server...")
                do {
                    // Add timeout to prevent infinite wait
                    let shutdownResponse = try await withThrowingTaskGroup(of: VoidResponse.self) { group in
                        // Task 1: Send shutdown to underlying server
                        group.addTask {
                            print("[DEBUG] SwiftPMBuildServer: Sending shutdown to underlying server...")
                            let response = try await self.connectionToUnderlyingBuildServer.send(request.params)
                            print("[DEBUG] SwiftPMBuildServer: Underlying server responded to shutdown")
                            return response
                        }

                        // Task 2: Timeout after 30 seconds
                        group.addTask {
                            try await Task.sleep(nanoseconds: 30_000_000_000)
                            print("[ERROR] SwiftPMBuildServer: Shutdown request timed out after 30 seconds!")
                            throw CancellationError()
                        }

                        // Wait for first task to complete
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                    print("[DEBUG] SwiftPMBuildServer: Calling local shutdown()...")
                    return await shutdown()
                } catch {
                    print("[ERROR] SwiftPMBuildServer: Shutdown failed with error: \(error)")
                    // Still try to shutdown locally even if underlying server didn't respond
                    return await shutdown()
                }
            }
        case let request as RequestAndReply<BuildTargetPrepareRequest>:
            await request.reply {
                var underlyingRequest = request.params
                underlyingRequest.targets.removeAll(where: \.isSwiftPMBuildServerTargetID )
                return try await connectionToUnderlyingBuildServer.send(underlyingRequest)
            }
        case let request as RequestAndReply<BuildTargetSourcesRequest>:
            await request.reply {
                var underlyingRequest = request.params
                underlyingRequest.targets.removeAll(where: \.isSwiftPMBuildServerTargetID)
                var sourcesResponse = try await connectionToUnderlyingBuildServer.send(underlyingRequest)
                for target in request.params.targets.filter({ $0.isSwiftPMBuildServerTargetID }) {
                    if target == .forPackageManifest {
                        sourcesResponse.items.append(await manifestSourcesItem())
                    } else {
                        await logToClient(.warning, "SwiftPM build server processed target sources request for unexpected target '\(target)'")
                    }
                }
                return sourcesResponse
            }
        case let request as RequestAndReply<InitializeBuildRequest>:
            await request.reply { try await self.initialize(request: request.params) }
        case let request as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
            await request.reply {
                if request.params.target.isSwiftPMBuildServerTargetID {
                    return try await manifestSourceKitOptions(request: request.params)
                } else {
                    return try await connectionToUnderlyingBuildServer.send(request.params)
                }
            }
        case let request as RequestAndReply<WorkspaceBuildTargetsRequest>:
            await request.reply {
                var targetsResponse = try await connectionToUnderlyingBuildServer.send(request.params)
                targetsResponse.targets.append(await manifestTarget())
                return targetsResponse
            }
        case let request as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
            await request.reply {
                await waitForBuildSystemUpdates(request: request.params)
            }
        default:
            await request.reply { throw ResponseError.methodNotFound(Request.method) }
        }
    }

    private func initialize(request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        if state != .waitingForInitializeRequest {
            logToClient(.warning, "Received initialization request while the build server is \(state)")
        }
        let underlyingInitializationResponse = try await connectionToUnderlyingBuildServer.send(request)
        let underlyingSourceKitData = SourceKitInitializeBuildResponseData(fromLSPAny: underlyingInitializationResponse.data)
        if underlyingSourceKitData?.watchers?.isEmpty == false {
            logToClient(.warning, "Underlying build server reported unexpected file watchers")
        }
        state = .waitingForInitializedNotification
        return InitializeBuildResponse(
            displayName: "SwiftPM Build Server",
            version: SwiftVersion.current.displayString,
            bspVersion: "2.2.0",
            capabilities: BuildServerCapabilities(),
            dataKind: .sourceKit,
            data: SourceKitInitializeBuildResponseData(
                indexDatabasePath: underlyingSourceKitData?.indexDatabasePath,
                indexStorePath: underlyingSourceKitData?.indexStorePath,
                outputPathsProvider: true,
                prepareProvider: true,
                sourceKitOptionsProvider: true,
                watchers: []
            ).encodeToLSPAny()
        )
    }

    private func manifestTarget() -> BuildTarget {
        // In the future, we should add a new target to represent plugin scripts so they can load the PackagePlugin module.
        return BuildTarget(
            id: .forPackageManifest,
            displayName: "Package Manifest",
            tags: [.notBuildable],
            languageIds: [.swift],
            dependencies: []
        )
    }

    private let versionSpecificManifestRegex = #/^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift$/#

    private func manifestSourcesItem() -> SourcesItem {
        let versionSpecificManifests = try? FileManager.default.contentsOfDirectory(
            at: packageRoot.asURL,
          includingPropertiesForKeys: nil
        ).compactMap { (url) -> SourceItem? in
          guard (try? versionSpecificManifestRegex.wholeMatch(in: url.lastPathComponent)) != nil else {
            return nil
          }
          return SourceItem(
            uri: DocumentURI(url),
            kind: .file,
            generated: false
          )
        }
        return SourcesItem(target: .forPackageManifest, sources: [
            SourceItem(
                uri: DocumentURI(packageRoot.appending(component: "Package.swift").asURL),
              kind: .file,
              generated: false
            )
        ] + (versionSpecificManifests ?? []))
    }

    private func manifestSourceKitOptions(request: TextDocumentSourceKitOptionsRequest) async throws -> TextDocumentSourceKitOptionsResponse? {
        guard request.target == .forPackageManifest else {
            throw ResponseError.unknown("Unknown target \(request.target)")
        }
        guard let path = try request.textDocument.uri.fileURL?.filePath else {
            throw ResponseError.unknown("Unknown manifest path for \(request.textDocument.uri.pseudoPath)")
        }
        let compilerArgs = try workspace.interpreterFlags(for: path) + [path.pathString]
        return TextDocumentSourceKitOptionsResponse(compilerArguments: compilerArgs)
    }

    private func shutdown() -> VoidResponse {
        print("[DEBUG] SwiftPMBuildServer: shutdown() called, setting state to .shutdown")
        state = .shutdown
        print("[DEBUG] SwiftPMBuildServer: shutdown() completed, state is now \(state)")
        return VoidResponse()
    }

    private func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
        await packageLoadingQueue.async {}.valuePropagatingCancellation
        return VoidResponse()
    }

    /// An event is relevant if it modifies a file that matches one of the file rules used by the SwiftPM workspace.
    private func fileEventShouldTriggerPackageReload(event: FileEvent) -> Bool {
        guard let fileURL = event.uri.fileURL else {
            return false
        }
        switch event.type {
        case .created, .deleted:
            // This is overly conservative, we may want to consider restricting it to file types which will be built.
            // However, the possibility of a plugin which might process an arbitrary file type makes this difficult.
            return true
        case .changed:
            return fileURL.lastPathComponent == "Package.swift" || fileURL.lastPathComponent == "Package.resolved" ||  fileURL.lastPathComponent.wholeMatch(of: versionSpecificManifestRegex) != nil
        default:
            logToClient(.warning, "received unknown file event type: '\(event.type)'")
            return false
        }
    }

    public func scheduleRegeneratingBuildDescription() {
        packageLoadingQueue.async { [buildSystem] in
            do {
                try await buildSystem.writePIF(buildParameters: buildSystem.buildParameters)
                self.connectionToUnderlyingBuildServer.send(OnWatchedFilesDidChangeNotification(changes: [
                    .init(uri: .init(buildSystem.buildParameters.pifManifest.asURL), type: .changed)
                ]))
                _ = try await self.connectionToUnderlyingBuildServer.send(WorkspaceWaitForBuildSystemUpdatesRequest())
            } catch {
                self.logToClient(.warning, "error regenerating build description: \(error)")
            }
        }
    }
}

extension BuildTargetIdentifier {
    static let swiftPMBuildServerTargetScheme = "swiftpm"

    static let forPackageManifest = BuildTargetIdentifier(uri: try! URI(string: "\(swiftPMBuildServerTargetScheme)://package-manifest"))

    var isSwiftPMBuildServerTargetID: Bool {
        uri.scheme == Self.swiftPMBuildServerTargetScheme
    }
}
#endif
