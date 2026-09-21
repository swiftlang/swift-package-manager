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
        let include = context.pluginWorkDirectoryURL
        let moduleMap = include.appending(path: "module.modulemap")
        let headerFile = include.appending(path: "SDL.h")
        let outputFile = context.pluginWorkDirectoryURL.appending(path: "SwiftSDL.swift")

        var sdlHeaderPath: [String] = []
        for dependency in target.dependencies {
            if case let .target(depTarget) = dependency, depTarget.name == "SDL" {
                sdlHeaderPath.append(depTarget.directoryURL.appending(path: "include").path)
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
                    moduleMap.path,
                    headerFile.path,
                    outputFile.path,
                ] + sdlHeaderPath,
                environment: environment,
                outputFiles: [
                    moduleMap,
                    headerFile,
                    outputFile,
                ]
            ),
        ]
    }
}
