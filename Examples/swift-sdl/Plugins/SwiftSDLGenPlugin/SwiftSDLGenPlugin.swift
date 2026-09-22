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
struct SwiftSDLGenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let generator = try context.tool(named: "SwiftSDLGenerator")
        let workDir = context.pluginWorkDirectoryURL
        let moduleMap = workDir.appending(path: "module.modulemap")
        let headerFile = workDir.appending(path: "SDL.h")
        let bindingsFile = workDir.appending(path: "SwiftSDL3.swift")
        let apinotesFile = workDir.appending(path: "SwiftSDL3.apinotes")

        var sdlHeaderPath: [String] = []
        for dependency in target.dependencies {
            if case let .target(depTarget) = dependency, depTarget.name == "SDL" {
                sdlHeaderPath += ["--header-path", depTarget.directoryURL.appending(path: "include").path]
            }
        }

        var environment = ["HOME": ProcessInfo.processInfo.environment["HOME"]!]
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            environment["DEVELOPER_DIR"] = developerDir
        }

        return [
            .buildCommand(
                displayName: "SDL API Generator",
                executable: generator.url,
                arguments: [
                    "--triple", "$(TRIPLE)",
                    "--sdk", "$(SDK)",
                    "--clang-resource-dir", "$(CLANG_RESOURCE_DIR)",
                    "--swift-resource-dir", "$(SWIFT_RESOURCE_DIR)",
                    "--modulemap-file", moduleMap.path,
                    "--header-file", headerFile.path,
                    "--bindings-file", bindingsFile.path,
                    "--apinotes-file", apinotesFile.path,
                ] + sdlHeaderPath,
                environment: environment,
                outputFiles: [
                    moduleMap,
                    headerFile,
                    bindingsFile,
                    apinotesFile
                ]
            ),
        ]
    }
}
