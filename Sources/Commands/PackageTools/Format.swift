//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import PackageModel

import class TSCBasic.Process
import enum TSCBasic.ProcessEnv

import enum TSCUtility.Diagnostics

extension SwiftPackageTool {
    struct Format: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "_format", shouldDisplay: false)

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(parsing: .captureForPassthrough,
                  help: "Pass flag through to the swift-format tool")
        var swiftFormatFlags: [String] = []

        func run(_ swiftTool: SwiftTool) async throws {
            // Look for swift-format binary.
            // FIXME: This should be moved to user toolchain.
            let swiftFormatInEnv = lookupExecutablePath(filename: ProcessEnv.vars["SWIFT_FORMAT"])
            guard let swiftFormat = swiftFormatInEnv ?? Process.findExecutable("swift-format").flatMap(AbsolutePath.init) else {
                swiftTool.observabilityScope.emit(error: "Could not find swift-format in PATH or SWIFT_FORMAT")
                throw TSCUtility.Diagnostics.fatalError
            }

            // Get the root package.
            let workspace = try swiftTool.getActiveWorkspace()

            guard let packagePath = try swiftTool.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            let package = try await workspace.loadRootPackage(
                at: packagePath,
                observabilityScope: swiftTool.observabilityScope
            )


            // Use the user provided flags or default to formatting mode.
            let formatOptions = swiftFormatFlags.isEmpty
                ? ["--mode", "format", "--in-place", "--parallel"]
                : swiftFormatFlags

            // Process each target in the root package.
            let paths = package.targets.flatMap { target in
                target.sources.paths.filter { file in
                    file.extension == SupportedLanguageExtension.swift.rawValue
                }
            }.map { $0.pathString }

            let args = [swiftFormat.pathString] + formatOptions + [packagePath.pathString] + paths
            print("Running:", args.map{ $0.spm_shellEscaped() }.joined(separator: " "))

            let result = try await TSCBasic.Process.popen(arguments: args)
            let output = try (result.utf8Output() + result.utf8stderrOutput())

            if result.exitStatus != .terminated(code: 0) {
                print("Non-zero exit", result.exitStatus)
            }
            if !output.isEmpty {
                print(output)
            }
        }
    }
}
