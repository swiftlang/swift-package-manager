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
extension SwiftSDLGenerator {
    func parseInterface(
        headerPaths: [FilePath],
        moduleDir: FilePath,
        moduleName: String
    ) async throws -> SourceFileSyntax {
        var synthArgs: [String] = [
            "-I", moduleDir.string,
            "-module-name", moduleName,
            "-target", triple.description,
        ]

        #if os(macos)
        let executable: Executable = .name("xcrun")
        synthArgs = ["swift-synthesize-interface"] + synthArgs
        #else
        let executable: Executable = .path(toolchain.appending("usr/bin/swift-synthesize-interface"))
        #endif

        if sdk.string != "none" {
            synthArgs += ["-sdk", sdk.string]
        }

        if clangResourceDir.string != "none" {
            synthArgs += ["-Xcc", "-resource-dir", "-Xcc", clangResourceDir.string]
        }

        if swiftResourceDir.string != "none" {
            synthArgs += ["-resource-dir", swiftResourceDir.string]
        }

        for headerPath in headerPaths {
            synthArgs += ["-I", headerPath.string]
        }

        guard let interface = try await Subprocess.run(
            executable,
            arguments: .init(synthArgs),
            output: .string(limit: .max),
            error: .currentStandardError).standardOutput
        else { fatalError() }

        return Parser.parse(source: interface)
    }
}
