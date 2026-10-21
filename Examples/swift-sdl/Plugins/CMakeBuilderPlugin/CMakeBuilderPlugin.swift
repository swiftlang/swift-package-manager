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
        let buildDir = context.pluginBuildDirectory

        var environment = ["HOME": ProcessInfo.processInfo.environment["HOME"]!]
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            environment["DEVELOPER_DIR"] = developerDir
        }

        let arguments: [CommandArgument] = [
            "--output-dir", .url(buildDir),
            "--triple", .triple,
            "--sysroot", .sysroot,
            .url(target.directoryURL),
        ]

        return [
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: arguments,
                environment: environment,
                buildProducts: [
                    .init(buildDir.appending(path: "libSDL3.dylib"), .when(platforms: [.macOS])),
                    .init(buildDir.appending(path: "libSDL3.so"), .when(platforms: [.android])),
                    .init(buildDir.appending(path: "SDL3.lib"), .when(platforms: [.windows])),
                    .init(buildDir.appending(path: "SDL3.dll"), .when(platforms: [.windows])),
                    .init(buildDir.appending(path: "SDL3.jar"), .when(platforms: [.android])),
                ],
                alwaysOutOfDate: true,
                .when(traits: ["SDL_shared"])
            ),
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: arguments + ["--static"],
                environment: environment,
                buildProducts: [
                    .init(buildDir.appending(path: "libSDL3.a"), .when(platforms: [.macOS, .android])),
                    .init(buildDir.appending(path: "SDL3-static.lib"), .when(platforms: [.windows])),
                    .init(buildDir.appending(path: "SDL3.jar"), .when(platforms: [.android])),
                ],
                alwaysOutOfDate: true,
                .when(traits: ["SDL_static"])
            ),
        ]
    }
}
