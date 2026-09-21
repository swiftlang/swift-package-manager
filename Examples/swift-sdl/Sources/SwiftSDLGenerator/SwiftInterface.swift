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
import Foundation
import Subprocess
import SwiftSyntax
import SwiftParser
#if canImport(System)
import System
#else
import SystemPackage
#endif

// Utility to load up the synthesized interface file for the C module into SwiftSyntax
public func parseInterface(headerPaths: [FilePath], moduleDir: FilePath, moduleName: String) async throws -> SourceFileSyntax {
    guard let sdkPath = try await run(.name("xcrun"), arguments: ["--show-sdk-path"], output: .string(limit: .max))
        .standardOutput?.trimmingCharacters(in: .newlines)
    else { fatalError() }
    
    var synthArgs: [String] = [
        "swift-synthesize-interface",
        "-I", moduleDir.string,
        "-module-name", moduleName,
        "-target", "arm64-apple-macos15",
        "-sdk", sdkPath
    ]

    for headerPath in headerPaths {
        synthArgs += ["-I", headerPath.string]
    }

    guard let interface = try await run(
        .name("xcrun"),
        arguments: .init(synthArgs),
        output: .string(limit: .max),
        error: .currentStandardError).standardOutput
    else { fatalError() }

    return Parser.parse(source: interface)
}
