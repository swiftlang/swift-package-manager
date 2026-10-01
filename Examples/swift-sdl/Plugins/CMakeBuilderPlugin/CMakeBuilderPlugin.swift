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
import PackagePlugin
import Foundation

@main
struct CMakeBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let builder = try context.tool(named: "CMakeBuilder")

        let buildDir = context.pluginWorkDirectoryURL.appending(path: "$(BUILD_SUBDIR)")
        let libSDL3 = buildDir.appending(path: "$(LIB_PREFIX)SDL3$(STATIC_LIB_EXTENSION)")
        let SDL3jar = buildDir.appending(path: "SDL3.jar")

        var environment = ["HOME": ProcessInfo.processInfo.environment["HOME"]!]
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            environment["DEVELOPER_DIR"] = developerDir
        }

        return [
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: [
                    "--output-dir", buildDir.path,
                    "--sdk", "$(SYSROOT)",
                    "--triple", "$(TRIPLE)",
                    target.directoryURL.path,
                ],
                environment: environment,
                productFiles: [
                    .init(buildDir.appending(path: "libSDL3.a"), platforms: [.macOS, .android]),
                    .init(buildDir.appending(path: "SDL3-static.lib"), platforms: [.windows]),
                    .init(buildDir.appending(path: "SDL3.jar"), platforms: [.android]),
                ],
                alwaysOutOfDate: true
            ),
        ]
    }
}
