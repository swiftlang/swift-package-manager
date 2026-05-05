//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
// import Build
import Commands
import CoreCommands


// import _InternalTestSupport
@testable import PackageModel
// import XCTest

// import ArgumentParser
import class TSCBasic.BufferedOutputByteStream
import protocol TSCBasic.OutputByteStream
import enum TSCBasic.SystemError
import var TSCBasic.stderrStream
import enum TSCBasic.JSON

extension SwiftCommandState {
    package static func makeMockState(
        outputStream: OutputByteStream = stderrStream,
        options: GlobalOptions,
        createPackagePath: Bool = false,
        hostTriple: Basics.Triple = .arm64Linux,
        targetInfo: JSON = UserToolchain.mockTargetInfo,
        fileSystem: any FileSystem = localFileSystem,
        environment: Environment = .current,
    ) throws -> SwiftCommandState {
        return try SwiftCommandState(
            outputStream: outputStream,
            options: options,
            toolWorkspaceConfiguration: .init(shouldInstallSignalHandlers: false),
            workspaceDelegateProvider: {
                CommandWorkspaceDelegate(
                    observabilityScope: $0,
                    outputHandler: $1,
                    progressHandler: $2,
                    inputHandler: $3
                )
            },
            workspaceLoaderProvider: {
                XcodeWorkspaceLoader(
                    fileSystem: $0,
                    observabilityScope: $1
                )
            },
            createPackagePath: createPackagePath,
            hostTriple: hostTriple,
            targetInfo: targetInfo,
            fileSystem: fileSystem,
            environment: environment
        )
    }
}
