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
        let libSDL3 = buildDir.appending(path: "libSDL3.a")
        let productsDir = URL(string: "file:/$(PRODUCTS_DIR)")!

        return [
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: [
                    "--output-dir", buildDir.path,
                    "--products-dir", "$(PRODUCTS_DIR)",
                    "--sdk", "$(SDK)",
                    "--triple", "$(TRIPLE)",
                    target.directoryURL.path,
                ],
                outputFiles: [libSDL3],
                alwaysOutOfDate: true
            ),
            .buildCommand(
                displayName: "Copy libSDL.a",
                executable: URL(string: "file:/$(COPY_CMD)")!,
                arguments: [
                    buildDir.appending(path: "libSDL3.a").path,
                    productsDir.path,
                ],
                inputFiles: [libSDL3],
                outputFiles: [productsDir.appending(path: "libSDL3.a")]
            ),
            .buildCommand(
                displayName: "Copy SDL3.jar",
                executable: URL(string: "file:/$(COPY_CMD)")!,
                arguments: [
                    "-L",
                    buildDir.appending(path: "SDL3.jar").path,
                    productsDir.path,
                ],
                inputFiles: [libSDL3],
                outputFiles: [productsDir.appending(path: "SDL3.jar")],
                targetPlatforms: [.android]
            ),
        ]
    }
}
