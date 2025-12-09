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
import ArgumentParser
import TSCBasic
import SwiftBuild
import BuildServerProtocol
import LanguageServerProtocol
import LanguageServerProtocolTransport
import CoreCommands
import Foundation
import PackageGraph
import SwiftPMBuildServer
import SPMBuildCore
import SwiftBuildSupport
import SystemPackage

struct BuildServer: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "experimental-build-server",
        abstract: "Launch a build server for Swift Packages",
        shouldDisplay: false
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        // Dup stdout and redirect the fd to stderr so that a careless print()
        // will not break our connection stream.
        let realStdout = try FileDescriptor.standardOutput.duplicate()
        _ = try FileDescriptor.standardError.duplicate(as: FileDescriptor.standardOutput)

        let realStdoutHandle = FileHandle(fileDescriptor: realStdout.rawValue, closeOnDealloc: false)

        let clientConnection = JSONRPCConnection(
            name: "client",
            protocol: MessageRegistry.bspProtocol,
            inFD: FileHandle.standardInput,
            outFD: realStdoutHandle,
            inputMirrorFile: nil,
            outputMirrorFile: nil
        )

        guard let buildSystem = try await swiftCommandState.createBuildSystem() as? SwiftBuildSystem else {
            throw ArgumentParser.ValidationError("Build server requires --build-system swiftbuild")
        }

        guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
            throw ArgumentParser.ValidationError("unknown package")
        }

        let server = try await SwiftPMBuildServer(
            packageRoot: packagePath,
            buildSystem: buildSystem,
            workspace: swiftCommandState.getActiveWorkspace(),
            connectionToClient: clientConnection,
            exitHandler: {_ in clientConnection.close() }
        )
        await withCheckedContinuation {continuation in
            clientConnection.start(receiveHandler: server, closeHandler: { continuation.resume() })
        }
    }
}
#endif
