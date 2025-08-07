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

import ArgumentParser
import TSCBasic
import SWBBuildServerProtocol
import CoreCommands
import Foundation
import PackageGraph
import SwiftPMBuildServer
import SPMBuildCore
import SwiftBuildSupport

struct BuildServer: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-server",
        abstract: "Launch a build server for Swift Packages"
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        // Dup stdout and redirect the fd to stderr so that a careless print()
        // will not break our connection stream.
        let realStdout = dup(STDOUT_FILENO)
        if realStdout == -1 {
            fatalError("failed to dup stdout: \(strerror(errno)!)")
        }
        if dup2(STDERR_FILENO, STDOUT_FILENO) == -1 {
            fatalError("failed to redirect stdout -> stderr: \(strerror(errno)!)")
        }

        let realStdoutHandle = FileHandle(fileDescriptor: realStdout, closeOnDealloc: false)

        let clientConnection = JSONRPCConnection(
            name: "client",
            protocol: bspRegistry,
            inFD: FileHandle.standardInput,
            outFD: realStdoutHandle,
            inputMirrorFile: nil,
            outputMirrorFile: nil
        )

        guard let buildSystem = try await swiftCommandState.createBuildSystem() as? SwiftBuildSystem else {
            print("Build server requires --build-system swiftbuild")
            Self.exit()
        }

        guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
            throw StringError("unknown package")
        }

        let server = try await SwiftPMBuildServer(packageRoot: packagePath, buildSystem: buildSystem, workspace: swiftCommandState.getActiveWorkspace(), connectionToClient: clientConnection, exitHandler: {_ in Self.exit() })
        clientConnection.start(
            receiveHandler: server,
            closeHandler: {
                Self.exit()
            }
        )

        // Park the main function by sleeping for 10 years.
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
        }
    }
}
