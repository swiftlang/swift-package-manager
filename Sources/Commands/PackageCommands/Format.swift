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
import PackageGraph
import TSCBasic
import Workspace
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

import enum TSCUtility.Diagnostics

extension SwiftPackageCommand {
    struct Format: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "_format", shouldDisplay: false,
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .private)
        var globalOptions: GlobalOptions

        @Argument(parsing: .captureForPassthrough,
                  help: "Pass flag through to the swift-format tool.")
        var swiftFormatFlags: [String] = []

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            // Look for swift-format binary.
            // FIXME: This should be moved to user toolchain.
            let swiftFormatInEnv = Basics.lookupExecutablePath(filename: Environment.current["SWIFT_FORMAT"])
            guard let swiftFormat = swiftFormatInEnv ?? Basics.lookupExecutablePath(filename: "swift-format") else {
                swiftCommandState.observabilityScope.emit(error: "Could not find swift-format in PATH or SWIFT_FORMAT")
                throw TSCUtility.Diagnostics.fatalError
            }

            // Get the root package.
            let workspace = try swiftCommandState.getActiveWorkspace()

            guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            let package = try await workspace.loadRootPackage(
                at: packagePath,
                observabilityScope: swiftCommandState.observabilityScope
            )


            // Use the user provided flags or default to formatting mode.
            let formatOptions = swiftFormatFlags.isEmpty
                ? ["--mode", "format", "--in-place", "--parallel"]
                : swiftFormatFlags

            // Process each target in the root package.
            let paths = package.modules.flatMap { target in
                target.sources.paths.filter { file in
                    file.extension == SupportedLanguageExtension.swift.rawValue
                }
            }.map { $0.pathString }

            let args = [swiftFormat.pathString] + formatOptions + [packagePath.pathString] + paths
            print("Running:", args.map{ $0.spm_shellEscaped() }.joined(separator: " "))

            let result = try await Subprocess.run(
                .path(FilePath(args[0])),
                arguments: Subprocess.Arguments(Array(args.dropFirst())),
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
            let output = (result.standardOutput ?? "") + (result.standardError ?? "")

            if !result.terminationStatus.isSuccess {
                print("Non-zero exit", result.terminationStatus)
            }
            if !output.isEmpty {
                print(output)
            }
        }
    }
}
