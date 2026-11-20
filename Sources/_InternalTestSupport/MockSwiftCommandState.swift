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

package import Basics
import Commands
package import CoreCommands

import PackageModel

package import class TSCBasic.BufferedOutputByteStream
package import protocol TSCBasic.OutputByteStream
package import enum TSCBasic.SystemError
package import var TSCBasic.stderrStream
package import enum TSCBasic.JSON

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
