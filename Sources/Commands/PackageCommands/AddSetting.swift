//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import PackageModelSyntax
import SwiftParser
import TSCBasic
import TSCUtility
import Workspace

extension SwiftPackageCommand {
    struct AddSetting: SwiftCommand {
        /// The Swift language setting that can be specified on the command line.
        enum SwiftSetting: String, Codable, ExpressibleByArgument, CaseIterable {
            case experimentalFeature
            case upcomingFeature
            case languageMode
            case strictMemorySafety = "StrictMemorySafety"
        }

        package static let configuration = CommandConfiguration(
            abstract: "Add a new setting to the manifest."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The target to add the setting to.")
        var target: String

        @Option(
            name: .customLong("swift"),
            parsing: .upToNextOption,
            help: "The Swift language setting(s) to add. Supported settings: \(SwiftSetting.allCases.map(\.rawValue).joined(separator: ", "))."
        )
        var _swiftSettings: [String]

        var swiftSettings: [(SwiftSetting, String)] {
            get throws {
                var settings: [(SwiftSetting, String)] = []
                for rawSetting in self._swiftSettings {
                    let (name, value) = rawSetting.spm_split(around: "=")

                    guard let setting = SwiftSetting(rawValue: name) else {
                        throw ValidationError("Unknown Swift language setting: \(name)")
                    }

                    settings.append((setting, value ?? ""))
                }

                return settings
            }
        }

        func run(_ swiftCommandState: SwiftCommandState) throws {
            if !self._swiftSettings.isEmpty {
                try Self.editSwiftSettings(
                    of: self.target,
                    using: swiftCommandState,
                    self.swiftSettings,
                    verbose: !self.globalOptions.logging.quiet
                )
            }
        }

        package static func editSwiftSettings(
            of target: String,
            using swiftCommandState: SwiftCommandState,
            _ settings: [(SwiftSetting, String)],
            verbose: Bool = false
        ) throws {
            let workspace = try swiftCommandState.getActiveWorkspace()
            guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            try self.applyEdits(
                packagePath: packagePath,
                workspace: workspace,
                target: target,
                swiftSettings: settings
            )
        }

        private static func applyEdits(
            packagePath: Basics.AbsolutePath,
            workspace: Workspace,
            target: String,
            swiftSettings: [(SwiftSetting, String)],
            verbose: Bool = false
        ) throws {
            // Load the manifest file
            let fileSystem = workspace.fileSystem
            let manifestPath = packagePath.appending(component: Manifest.filename)

            for (setting, value) in swiftSettings {
                let manifestContents: ByteString
                do {
                    manifestContents = try fileSystem.readFileContents(manifestPath)
                } catch {
                    throw StringError("cannot find package manifest in \(manifestPath)")
                }

                // Parse the manifest.
                let manifestSyntax = manifestContents.withData { data in
                    data.withUnsafeBytes { buffer in
                        buffer.withMemoryRebound(to: UInt8.self) { buffer in
                            Parser.parse(source: buffer)
                        }
                    }
                }

                let editResult: PackageEditResult

                switch setting {
                case .experimentalFeature:
                    editResult = try AddSwiftSetting.experimentalFeature(
                        to: target,
                        name: value,
                        manifest: manifestSyntax
                    )
                case .upcomingFeature:
                    editResult = try AddSwiftSetting.upcomingFeature(
                        to: target,
                        name: value,
                        manifest: manifestSyntax
                    )
                case .languageMode:
                    guard let mode = SwiftLanguageVersion(string: value) else {
                        throw ValidationError("Unknown Swift language mode: \(value)")
                    }

                    editResult = try AddSwiftSetting.languageMode(
                        to: target,
                        mode: mode,
                        manifest: manifestSyntax
                    )
                case .strictMemorySafety:
                    guard value.isEmpty || value == SwiftSetting.strictMemorySafety.rawValue else {
                        throw ValidationError("'strictMemorySafety' does not support argument '\(value)'")
                    }

                    editResult = try AddSwiftSetting.strictMemorySafety(
                        to: target,
                        manifest: manifestSyntax
                    )
                }

                try editResult.applyEdits(
                    to: fileSystem,
                    manifest: manifestSyntax,
                    manifestPath: manifestPath,
                    verbose: verbose
                )
            }
        }
    }
}
