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

import Basics
import SWBBuildServerProtocol
import Foundation
import SPMBuildCore
import SwiftBuildSupport
import SwiftBuild
import SWBBuildService
import Workspace

public actor SwiftPMBuildServer: QueueBasedMessageHandler {
    private let session: SwiftBuildSystem.LongLivedBuildServiceSession
    private let underlyingBuildServer: SWBBuildServer
    private let connectionToUnderlyingBuildServer: LocalConnection
    private let packageRoot: Basics.AbsolutePath
    private let buildSystem: SwiftBuildSystem
    private let workspace: Workspace

    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "build-server-message-handling",
        createLoggingScope: false
    )
    public let messageHandlingQueue = AsyncQueue<BuildSystemMessageDependencyTracker>()
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
        self.packageRoot = packageRoot
        self.buildSystem = buildSystem
        self.workspace = workspace
        self.connectionToClient = connectionToClient
        self.exitHandler = exitHandler
        // TODO: Report session creation diagnostics, tear the session down cleanly on exit
        self.session = try await buildSystem.createLongLivedSession(name: "swiftpm-build-server")
        // TODO: properly teardown connections on exit
        self.connectionToUnderlyingBuildServer = LocalConnection(receiverName: "underlying-swift-build-server")
        let connectionFromUnderlyingBuildServer = LocalConnection(receiverName: "swiftpm-build-server")
        // TODO: fix derived data path, cleanup configured targets list computation
        let buildrequest = try await self.buildSystem.makeBuildRequest(session: session.session, configuredTargets: [.init(rawValue: "ALL-INCLUDING-TESTS")], derivedDataPath: self.buildSystem.buildParameters.buildPath, genSymbolGraph: false)
        self.underlyingBuildServer = SWBBuildServer(session: session.session, buildRequest: buildrequest, connectionToClient: connectionFromUnderlyingBuildServer, exitHandler: { _ in })
        connectionToUnderlyingBuildServer.start(handler: underlyingBuildServer)
        connectionFromUnderlyingBuildServer.start(handler: self)
    }

    public func handle(notification: some NotificationType) async {
        switch notification {
        case is OnBuildExitNotification:
            connectionToUnderlyingBuildServer.send(notification)
            if state == .shutdown {
                exitHandler(0)
            } else {
                exitHandler(1)
            }
        case is OnBuildInitializedNotification:
            connectionToUnderlyingBuildServer.send(notification)
            state = .running
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
        default:
            break
        }
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
                _ = try await connectionToUnderlyingBuildServer.send(request.params)
                return await shutdown()
            }
        case let request as RequestAndReply<BuildTargetPrepareRequest>:
            await request.reply {
                for target in request.params.targets.filter({ $0.isSwiftPMBuildServerTargetID }) {
                    // Error
                }
                var underlyingRequest = request.params
                underlyingRequest.targets.removeAll(where: { $0.isSwiftPMBuildServerTargetID })
                return try await connectionToUnderlyingBuildServer.send(underlyingRequest)
            }
        case let request as RequestAndReply<BuildTargetSourcesRequest>:
            await request.reply {
                var underlyingRequest = request.params
                underlyingRequest.targets.removeAll(where: { $0.isSwiftPMBuildServerTargetID })
                var sourcesResponse = try await connectionToUnderlyingBuildServer.send(underlyingRequest)
                for target in request.params.targets.filter({ $0.isSwiftPMBuildServerTargetID }) {
                    if target == .forPackageManifest {
                        sourcesResponse.items.append(await manifestSourcesItem())
                    } else {
                        // Unexpected target
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
        guard state == .waitingForInitializeRequest else {
            throw ResponseError.unknown("Received initialization request while the build server is \(state)")
        }
        let underlyingInitializationResponse = try await connectionToUnderlyingBuildServer.send(request)
        let underlyingSourceKitData = SourceKitInitializeBuildResponseData(fromLSPAny: underlyingInitializationResponse.data)
        // TODO: Check the underlying build server didn't register any file watchers we didn't expect
        state = .waitingForInitializedNotification
        scheduleRegeneratingBuildDescription()
        return InitializeBuildResponse(
            displayName: "SwiftPM Build Server",
            version: "",
            bspVersion: "2.2.0",
            capabilities: BuildServerCapabilities(),
            dataKind: .sourceKit,
            data: SourceKitInitializeBuildResponseData(
                indexDatabasePath: underlyingSourceKitData?.indexDatabasePath,
                indexStorePath: underlyingSourceKitData?.indexStorePath,
                outputPathsProvider: true,
                prepareProvider: true,
                sourceKitOptionsProvider: true,
                watchers: [] // TODO: add watchers
            ).encodeToLSPAny()
        )
    }

    private func manifestTarget() -> BuildTarget {
        // TODO: there should be a target to represent plugin scripts
        return BuildTarget(
            id: .forPackageManifest,
            displayName: "Package Manifest",
            tags: [.notBuildable],
            languageIds: [.swift],
            dependencies: []
        )
    }

    private func manifestSourcesItem() -> SourcesItem {
        // TODO: share the code for discovering version-specific manifests with regular manifest loading, then potentially remove the packageRoot property
        let packageManifestName = #/^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift$/#
        let versionSpecificManifests = try? FileManager.default.contentsOfDirectory(
            at: packageRoot.asURL,
          includingPropertiesForKeys: nil
        ).compactMap { (url) -> SourceItem? in
          guard (try? packageManifestName.wholeMatch(in: url.lastPathComponent)) != nil else {
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

    private func shutdown() -> SWBBuildServerProtocol.VoidResponse {
        state = .shutdown
        return VoidResponse()
    }

    private func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> SWBBuildServerProtocol.VoidResponse {
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
            // TODO: this is overly conservative
            return true
        case .changed:
            // TODO: check for changes to version specific manifests too
            return fileURL.lastPathComponent == "Package.swift" || fileURL.lastPathComponent == "Package.resolved"
        default:
            // TODO: log unknown change type
            return false
        }
    }

    public func scheduleRegeneratingBuildDescription() {
        packageLoadingQueue.async { [buildSystem, session] in
            do {
                // TODO: should the PIF update API be exposed as API on SWBBuildServer somehow so we don't need to talk to the session directly?
                try await buildSystem.writePIF()
                try await session.session.loadWorkspace(containerPath: buildSystem.buildParameters.pifManifest.pathString)
                try await session.session.setSystemInfo(.default())
                await self.underlyingBuildServer.scheduleRegeneratingBuildDescription()
                _ = try await self.connectionToUnderlyingBuildServer.send(WorkspaceWaitForBuildSystemUpdatesRequest())
            } catch {
                
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
