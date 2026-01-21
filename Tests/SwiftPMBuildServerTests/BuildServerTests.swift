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
import Foundation
import PackageModel
import BuildServerProtocol
import LanguageServerProtocol
import LanguageServerProtocolTransport
import SwiftPMBuildServer
import _InternalTestSupport
import Testing

final fileprivate class NotificationCollectingMessageHandler: MessageHandler {
    func handle(_ notification: some NotificationType) {}
    func handle<Request>(_ request: Request, id: RequestID, reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void) where Request : RequestType {}
}

fileprivate func withSwiftPMBSP(fixtureName: String, body: (Connection, NotificationCollectingMessageHandler, AbsolutePath) async throws -> Void) async throws {
    await withKnownIssue("Tests occasionally fail to load build description in CI", isIntermittent: true) {
        try await fixture(name: fixtureName) { fixture in
            let inPipe = Pipe()
            let outPipe = Pipe()
            let connection = JSONRPCConnection(
                name: "bsp-connection",
                protocol: MessageRegistry.bspProtocol,
                inFD: inPipe.fileHandleForReading,
                outFD: outPipe.fileHandleForWriting
            )
            let bspProcess = Process()
            bspProcess.standardOutputPipe = inPipe
            bspProcess.standardInput = outPipe
            let execPath = SwiftPM.xctestBinaryPath(for: "swift-package").pathString
            bspProcess.executableURL = URL(filePath: execPath)
            bspProcess.arguments = ["--package-path", fixture.pathString, "experimental-build-server", "--build-system", "swiftbuild"]
            async let terminationPromise: Void = try await bspProcess.run()
            let notificationCollector = NotificationCollectingMessageHandler()
            connection.start(receiveHandler: notificationCollector)
            _ = try await connection.send(
                InitializeBuildRequest(
                    displayName: "test-bsp-client",
                    version: "1.0.0",
                    bspVersion: "2.2.0",
                    rootUri: URI(URL(filePath: fixture.pathString)),
                    capabilities: .init(languageIds: [.swift, .c, .objective_c, .cpp, .objective_cpp])
                )
            )
            connection.send(OnBuildInitializedNotification())
            _ = try await connection.send(WorkspaceWaitForBuildSystemUpdatesRequest())
            try await body(connection, notificationCollector, fixture)
            _ = try await connection.send(BuildShutdownRequest())
            connection.send(OnBuildExitNotification())
            connection.close()
            try await terminationPromise
        }
    }
}

@Suite(
    .disabled(if: ProcessInfo.hostOperatingSystem == .windows, "This hangs intermittently on Windows in CI using the native build system")
)
struct SwiftPMBuildServerTests {
    @Test
    func lifecycleBasics() async throws {
        try await withSwiftPMBSP(fixtureName: "Miscellaneous/Simple") { _, _, _ in
            // Do nothing, but ensure the surrounding initialization and shutdown complete successfully.
        }
    }

    @Test
    func buildTargetsListBasics() async throws {
        try await withSwiftPMBSP(fixtureName: "Miscellaneous/Simple") { connection, _, _ in
            let response = try await connection.send(WorkspaceBuildTargetsRequest())
            #expect(response.targets.count == 2)
            #expect(response.targets.map(\.displayName).sorted() == ["Foo", "Package Manifest"])
        }
    }

    @Test
    func sourcesItemsBasics() async throws {
        try await withSwiftPMBSP(fixtureName: "Miscellaneous/Simple") { connection, _, _ in
            let targetResponse = try await connection.send(WorkspaceBuildTargetsRequest())
            #expect(targetResponse.targets.count == 2)
            #expect(targetResponse.targets.map(\.displayName).sorted() == ["Foo", "Package Manifest"])

            let fooID = try #require(targetResponse.targets.first(where: { $0.displayName == "Foo" })).id
            let sourcesResponse = try await connection.send(BuildTargetSourcesRequest(targets: [fooID]))
            let item = try #require(sourcesResponse.items.only?.sources.only)
            #expect(item.kind == .file)
            #expect(item.uri.fileURL?.lastPathComponent == "Foo.swift")
        }
    }

    @Test
    func compilerArgsBasics() async throws {
        try await withSwiftPMBSP(fixtureName: "Miscellaneous/Simple") { connection, _, _ in
            let targetResponse = try await connection.send(WorkspaceBuildTargetsRequest())
            #expect(targetResponse.targets.count == 2)
            #expect(targetResponse.targets.map(\.displayName).sorted() == ["Foo", "Package Manifest"])

            let fooID = try #require(targetResponse.targets.first(where: { $0.displayName == "Foo" })).id
            let sourcesResponse = try await connection.send(BuildTargetSourcesRequest(targets: [fooID]))
            let item = try #require(sourcesResponse.items.only?.sources.only)
            #expect(item.kind == .file)
            #expect(item.uri.fileURL?.lastPathComponent == "Foo.swift")

            _ = try await connection.send(BuildTargetPrepareRequest(targets: [fooID]))

            let settingsResponse = try #require(try await connection.send(TextDocumentSourceKitOptionsRequest(textDocument: TextDocumentIdentifier(item.uri), target: fooID, language: .swift)))
            #expect(settingsResponse.compilerArguments.contains(["-module-name", "Foo"]))
            try await AsyncProcess.checkNonZeroExit(arguments: [UserToolchain.default.swiftCompilerPath.pathString, "-typecheck"] + settingsResponse.compilerArguments)
        }
    }

    @Test
    func packageReloadBasics() async throws {
        try await withSwiftPMBSP(fixtureName: "Miscellaneous/Simple") { connection, _, fixturePath in
            let targetResponse = try await connection.send(WorkspaceBuildTargetsRequest())
            #expect(targetResponse.targets.count == 2)
            #expect(targetResponse.targets.map(\.displayName).sorted() == ["Foo", "Package Manifest"])

            let fooID = try #require(targetResponse.targets.first(where: { $0.displayName == "Foo" })).id
            let sourcesResponse = try await connection.send(BuildTargetSourcesRequest(targets: [fooID]))
            let sourcesItem = try #require(sourcesResponse.items.only)
            #expect(sourcesItem.sources.count == 1)
            #expect(sourcesItem.sources.map(\.uri.fileURL?.lastPathComponent).sorted() == ["Foo.swift"])

            try localFileSystem.writeFileContents(fixturePath.appending(component: "Bar.swift"), body: {
                $0.write("public let baz = \"hello\"")
            })

            connection.send(OnWatchedFilesDidChangeNotification(changes: [
                .init(uri: .init(.init(filePath: fixturePath.appending(component: "Bar.swift").pathString)), type: .created)
            ]))
            _ = try await connection.send(WorkspaceWaitForBuildSystemUpdatesRequest())

            let updatedSourcesResponse = try await connection.send(BuildTargetSourcesRequest(targets: [fooID]))
            let updatedSourcesItem = try #require(updatedSourcesResponse.items.only)
            #expect(updatedSourcesItem.sources.count == 2)
            #expect(updatedSourcesItem.sources.map(\.uri.fileURL?.lastPathComponent).sorted() == ["Bar.swift", "Foo.swift"])
        }
    }

    @Test
    func manifestArgs() async throws {
        try await withSwiftPMBSP(fixtureName: "Miscellaneous/VersionSpecificManifest") { connection, _, _ in
            let targetResponse = try await connection.send(WorkspaceBuildTargetsRequest())
            #expect(targetResponse.targets.count == 2)
            #expect(targetResponse.targets.map(\.displayName).sorted() == ["Foo", "Package Manifest"])

            let manifestTarget = try #require(targetResponse.targets.first(where: { $0.displayName == "Package Manifest" }))
            #expect(manifestTarget.tags.contains(.notBuildable))
            let manifestID = manifestTarget.id
            let sourcesResponse = try await connection.send(BuildTargetSourcesRequest(targets: [manifestID]))
            let manifestItems = try #require(sourcesResponse.items.only?.sources)
            #expect(manifestItems.map(\.uri.fileURL?.lastPathComponent).sorted() == ["Package.swift", "Package@swift-5.0.swift"])
            for item in manifestItems {
                let settingsResponse = try #require(try await connection.send(TextDocumentSourceKitOptionsRequest(textDocument: TextDocumentIdentifier(item.uri), target: manifestID, language: .swift)))
                try await AsyncProcess.checkNonZeroExit(arguments: [UserToolchain.default.swiftCompilerPath.pathString, "-typecheck"] + settingsResponse.compilerArguments)
            }
        }
    }
}
#endif
