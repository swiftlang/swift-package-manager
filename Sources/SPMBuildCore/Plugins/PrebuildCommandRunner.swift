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

import struct TSCBasic.StringError

// SPMBuildCore is an exported target, so its Subprocess and System dependencies must not leak into the module's
// required modules (see DefaultPluginScriptRunner.swift).
#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import Subprocess
#if canImport(System)
@_implementationOnly import System
#else
@_implementationOnly import SystemPackage
#endif
#else
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif
#endif

/// Runs a plugin prebuild command to completion and returns its combined stdout and stderr.
///
/// Throws a `StringError` containing the command line and its output if the command exits unsuccessfully.
package func runPrebuildCommand(
    commandLine: [String],
    environment: Basics.Environment,
    description: String
) async throws -> String {
    let result = try await Subprocess.run(
        .path(FilePath(commandLine[0])),
        arguments: Subprocess.Arguments(Array(commandLine.dropFirst())),
        environment: .custom(filtering: environment),
        output: .bytes(limit: .max),
        error: .combinedWithOutput
    )
    let output = String(decoding: result.standardOutput, as: UTF8.self)
    guard result.terminationStatus.isSuccess else {
        throw StringError("failed: \(description)\n\n\(output)")
    }
    return output
}
