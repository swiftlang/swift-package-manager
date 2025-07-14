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

@_spi(SwiftPMInternal)
import CoreCommands

import Foundation

import OrderedCollections

import PackageGraph
import PackageModel

import SPMBuildCore
import SwiftFixIt

import var TSCBasic.stdoutStream

struct MigrateOptions: ParsableArguments {
    @Option(
        name: .customLong("target"),
        help: "The targets to migrate to specified set of features."
    )
    var _targets: String?

    var targets: OrderedSet<String> {
        self._targets.flatMap { OrderedSet($0.components(separatedBy: ",")) } ?? []
    }

    @Option(
        name: .customLong("to-feature"),
        help: "The Swift language upcoming/experimental feature to migrate to."
    )
    var _features: String

    var features: Set<String> {
        Set(self._features.components(separatedBy: ","))
    }
}

extension SwiftPackageCommand {
    struct Migrate: AsyncSwiftCommand {
        package static let configuration = CommandConfiguration(
            abstract: "Migrate a package or its individual targets to use the given set of features."
        )

        @OptionGroup()
        public var globalOptions: GlobalOptions

        @OptionGroup()
        var options: MigrateOptions

        public func run(_ swiftCommandState: SwiftCommandState) async throws {
            let toolchain = try swiftCommandState.productsBuildParameters.toolchain

            let supportedFeatures = try Dictionary(
                uniqueKeysWithValues: toolchain.swiftCompilerSupportedFeatures
                    .map { ($0.name, $0) }
            )

            // First, let's validate that all of the features are supported
            // by the compiler and are migratable.

            var features: [SwiftCompilerFeature] = []
            for name in self.options.features {
                guard let feature = supportedFeatures[name] else {
                    let migratableFeatures = supportedFeatures.map(\.value).filter(\.migratable).map(\.name)
                    throw ValidationError(
                        "Unsupported feature: \(name). Available features: \(migratableFeatures.joined(separator: ", "))"
                    )
                }

                guard feature.migratable else {
                    throw ValidationError("Feature '\(name)' is not migratable")
                }

                features.append(feature)
            }

            var targets = self.options.targets

            let buildSystem = try await createBuildSystem(
                swiftCommandState,
                targets: targets,
                features: features
            )

            // Next, let's build all of the individual targets or the
            // whole project to get diagnostic files.
            print("> Starting the build")
            var diagnosticsPaths: [String: [AbsolutePath]] = [:]
            if !targets.isEmpty {
                for target in targets {
                    let buildResult = try await buildSystem.build(subset: .target(target))
                    diagnosticsPaths.merge(try buildResult.serializedDiagnosticPathsByTargetName.get(), uniquingKeysWith: { $0 + $1 })
                }
            } else {
                diagnosticsPaths = try await buildSystem.build(subset: .allIncludingTests).serializedDiagnosticPathsByTargetName.get()
            }

            var summary = SwiftFixIt.Summary(numberOfFixItsApplied: 0, numberOfFilesChanged: 0)
            let graph = try await buildSystem.getPackageGraph()
            if targets.isEmpty {
                targets = OrderedSet(graph.rootPackages.flatMap { $0.manifest.targets.filter { $0.type != .plugin }.map(\.name) })
            }
            print("> Applying fix-its")
            let fixItDuration = try ContinuousClock().measure {
                for target in targets {
                    let fixit = try SwiftFixIt(
                        diagnosticFiles: Array(diagnosticsPaths[target] ?? []),
                        categories: Set(features.flatMap(\.categories)),
                        excludedSourceDirectories: [swiftCommandState.scratchDirectory],
                        fileSystem: swiftCommandState.fileSystem
                    )
                    summary += try fixit.applyFixIts()
                }
            }

            // Report the changes.
            do {
                var message = "> Applied \(summary.numberOfFixItsApplied) fix-it"
                if summary.numberOfFixItsApplied != 1 {
                    message += "s"
                }
                message += " in \(summary.numberOfFilesChanged) file"
                if summary.numberOfFilesChanged != 1 {
                    message += "s"
                }
                message += " ("
                message += fixItDuration.formatted(
                    .units(
                        allowed: [.seconds],
                        width: .narrow,
                        fractionalPart: .init(lengthLimits: 0 ... 3, roundingRule: .up)
                    )
                )
                message += ")"

                print(message)
            }

            // Once the fix-its were applied, it's time to update the
            // manifest with newly adopted feature settings.

            print("> Updating manifest")
            for target in targets {
                swiftCommandState.observabilityScope.emit(debug: "Adding feature(s) to '\(target)'")
                try self.updateManifest(
                    for: target,
                    add: features,
                    using: swiftCommandState
                )
            }
        }

        private func createBuildSystem(
            _ swiftCommandState: SwiftCommandState,
            targets: OrderedSet<String>,
            features: [SwiftCompilerFeature]
        ) async throws -> BuildSystem {
            let toolsBuildParameters = try swiftCommandState.toolsBuildParameters
            let destinationBuildParameters = try swiftCommandState.productsBuildParameters

            let modulesGraph = try await swiftCommandState.loadPackageGraph()

            let addFeaturesToModule = { (module: ResolvedModule) in
                for feature in features {
                    module.underlying.buildSettings.add(.init(values: feature.migrationFlags), for: .OTHER_SWIFT_FLAGS)
                }
            }

            if !targets.isEmpty {
                targets.lazy.compactMap {
                    modulesGraph.module(for: $0)
                }.forEach(addFeaturesToModule)
            } else {
                for package in modulesGraph.rootPackages {
                    package.modules.filter {
                        $0.type != .plugin
                    }.forEach(addFeaturesToModule)
                }
            }

            return try await swiftCommandState.createBuildSystem(
                traitConfiguration: .init(),
                // Don't attempt to cache manifests with temporary
                // feature flags added just for migration purposes.
                cacheBuildManifest: false,
                productsBuildParameters: destinationBuildParameters,
                toolsBuildParameters: toolsBuildParameters,
                // command result output goes on stdout
                // ie "swift build" should output to stdout
                packageGraphLoader: {
                    modulesGraph
                },
                outputStream: TSCBasic.stdoutStream,
                observabilityScope: swiftCommandState.observabilityScope
            )
        }

        private func updateManifest(
            for target: String,
            add features: [SwiftCompilerFeature],
            using swiftCommandState: SwiftCommandState
        ) throws {
            typealias SwiftSetting = SwiftPackageCommand.AddSetting.SwiftSetting

            let settings: [(SwiftSetting, String)] = try features.map {
                (try $0.swiftSetting, $0.name)
            }

            do {
                try SwiftPackageCommand.AddSetting.editSwiftSettings(
                    of: target,
                    using: swiftCommandState,
                    settings,
                    verbose: !self.globalOptions.logging.quiet
                )
            } catch {
                try swiftCommandState.observabilityScope.emit(
                    error: """
                    Could not update manifest for '\(target)' (\(error)). \
                    Please enable '\(
                        features.map { try $0.swiftSettingDescription }
                            .joined(separator: ", ")
                    )' features manually
                    """
                )
            }
        }

        public init() {}
    }
}

fileprivate extension SwiftCompilerFeature {
    /// Produce the set of command-line flags to pass to the compiler to enable migration for this feature.
    var migrationFlags: [String] {
        precondition(migratable)

        switch self {
        case .upcoming(name: let name, migratable: _, categories: _, enabledIn: _):
            return ["-Xfrontend", "-enable-upcoming-feature", "-Xfrontend", "\(name):migrate"]
        case .experimental(name: let name, migratable: _, categories: _):
            return ["-Xfrontend", "-enable-experimental-feature", "-Xfrontend", "\(name):migrate"]
        case .optional(name: _, migratable: _, categories: _, flagName: let flagName):
            let flags = flagName.split(separator: " ")
            var resultFlags: [String] = []
            for (index, flag) in flags.enumerated() {
                resultFlags.append("-Xfrontend")
                if index == flags.endIndex - 1 {
                    resultFlags.append(String(flag) + ":migrate")
                } else {
                    resultFlags.append(String(flag))
                }
            }

            return resultFlags
        }
    }

    /// Produce the Swift setting corresponding to this compiler feature.
    var swiftSetting: SwiftPackageCommand.AddSetting.SwiftSetting {
        get throws {
            switch self {
            case .upcoming:
                return .upcomingFeature
            case .experimental:
                return .experimentalFeature
            case .optional(name: "StrictMemorySafety", migratable: _, categories: _, flagName: _):
                return .strictMemorySafety
            case .optional(name: let name, migratable: _, categories: _, flagName: _):
                throw InternalError("Unsupported optional feature: \(name)")
            }
        }
    }

    var swiftSettingDescription: String {
        get throws {
            switch self {
            case .upcoming(name: let name, migratable: _, categories: _, enabledIn: _):
                return #".enableUpcomingFeature("\#(name)")"#
            case .experimental(name: let name, migratable: _, categories: _):
                return #".enableExperimentalFeature("\#(name)")"#
            case .optional(name: "StrictMemorySafety", migratable: _, categories: _, flagName: _):
                return ".strictMemorySafety()"
            case .optional(name: let name, migratable: _, categories: _, flagName: _):
                throw InternalError("Unsupported optional feature: \(name)")
            }
        }
    }
}
