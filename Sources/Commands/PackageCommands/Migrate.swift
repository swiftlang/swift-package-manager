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
import enum PackageModelSyntax.ManifestEditError

import SPMBuildCore
import SwiftFixIt

import var TSCBasic.stdoutStream

struct MigrateOptions: ParsableArguments {
    @Option(
        name: .customLong("target"),
        help: "A comma-separated list of targets to migrate. (default: all Swift targets)"
    )
    var _targets: String?

    var targets: OrderedSet<String> {
        self._targets.flatMap { OrderedSet($0.components(separatedBy: ",")) } ?? []
    }

    @Option(
        name: .customLong("to-feature"),
        help: "A comma-separated list of Swift language features to migrate to."
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

        @OptionGroup(visibility: .hidden)
        public var globalOptions: GlobalOptions

        @OptionGroup()
        var options: MigrateOptions

        public func run(_ swiftCommandState: SwiftCommandState) async throws {
            // First, validate and resolve the requested feature names.
            let features = try self.resolveRequestedFeatures(swiftCommandState)

            let targets = self.options.targets

            let buildSystem = try await createBuildSystem(
                swiftCommandState,
                targets: targets,
                features: features
            )

            // Next, let's build all of the individual targets or the
            // whole project to get diagnostic files.

            print("> Starting the build")
            if !targets.isEmpty {
                for target in targets {
                    try await buildSystem.build(subset: .target(target))
                }
            } else {
                try await buildSystem.build(subset: .allIncludingTests)
            }

            // Determine all of the targets we need up update.
            let buildPlan = try buildSystem.buildPlan

            var modules = [String: [AbsolutePath]]()
            if !targets.isEmpty {
                for buildDescription in buildPlan.buildModules
                    where targets.contains(buildDescription.module.name) {
                    modules[buildDescription.module.name, default: []].append(contentsOf: buildDescription.diagnosticFiles)
                }
            } else {
                let graph = try await buildSystem.getPackageGraph()
                for buildDescription in buildPlan.buildModules
                    where graph.isRootPackage(buildDescription.package)
                {
                    let module = buildDescription.module
                    // FIXME: Plugin target init does not have a Swift settings
                    // parameter, so we won't be able to enable the feature.
                    // Exclude plugins from migration.
                    guard module.type != .plugin, !module.implicit else {
                        continue
                    }
                    modules[buildDescription.module.name, default: []].append(contentsOf: buildDescription.diagnosticFiles)
                }
            }

            // If the build suceeded, let's extract all of the diagnostic
            // files from build plan and feed them to the fix-it tool.

            print("> Applying fix-its")

            var summary = SwiftFixIt.Summary(numberOfFixItsApplied: 0, numberOfFilesChanged: 0)
            let fixItDuration = try ContinuousClock().measure {
                let applier = try SwiftFixIt(
                    diagnosticFiles: modules.values.joined(),
                    categories: Set(features.flatMap(\.categories)),
                    excludedSourceDirectories: [swiftCommandState.scratchDirectory],
                    fileSystem: swiftCommandState.fileSystem
                )
                summary = try applier.applyFixIts()
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
            //
            // Loop over a sorted array to produce deterministic results and
            // order of diagnostics.

            print("> Updating manifest")
            for name in modules.keys.sorted() {
                swiftCommandState.observabilityScope.emit(debug: "Adding feature(s) to '\(name)'")
                try self.updateManifest(
                    for: name,
                    add: features,
                    using: swiftCommandState
                )
            }
        }

        /// Resolves the requested feature names.
        ///
        /// - Returns: An array of resolved features, sorted by name.
        private func resolveRequestedFeatures(
            _ swiftCommandState: SwiftCommandState
        ) throws -> [SwiftCompilerFeature] {
            let toolchain = try swiftCommandState.productsBuildParameters.toolchain

            // Query the compiler for supported features.
            let supportedFeatures = try toolchain.swiftCompilerSupportedFeatures

            var resolvedFeatures: [SwiftCompilerFeature] = []

            // Resolve the requested feature names, validating that they are
            // supported by the compiler and migratable.
            for name in self.options.features {
                let feature = supportedFeatures.first { $0.name == name }

                guard let feature else {
                    let migratableCommaSeparatedFeatures = supportedFeatures
                        .filter(\.migratable)
                        .map(\.name)
                        .sorted()
                        .joined(separator: ", ")

                    throw ValidationError(
                        "Unsupported feature '\(name)'. Available features: \(migratableCommaSeparatedFeatures)"
                    )
                }

                guard feature.migratable else {
                    throw ValidationError("Feature '\(name)' is not migratable")
                }

                resolvedFeatures.append(feature)
            }

            return resolvedFeatures.sorted { lhs, rhs in
                lhs.name < rhs.name
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
                var message =
                    "Could not update manifest to enable requested features for target '\(target)' (\(error))"

                // Do not suggest manual addition if something else is wrong or
                // if the error implies that it cannot be done.
                if let error = error as? ManifestEditError {
                    switch error {
                    case .cannotFindPackage,
                         .cannotAddSettingsToPluginTarget,
                         .existingDependency:
                        break
                    case .cannotFindArrayLiteralArgument,
                         // This means the target could not be found
                         // syntactically, not that it does not exist.
                         .cannotFindTargets,
                         .cannotFindTarget,
                         // This means the swift-tools-version is lower than
                         // the version where one of the setting was introduced.
                         .oldManifest:
                        let settings = try features.map {
                            try $0.swiftSettingDescription
                        }.joined(separator: ", ")

                        message += """
                        . Please enable them manually by adding the following Swift settings to the target: \
                        '\(settings)'
                        """
                    }
                }

                swiftCommandState.observabilityScope.emit(error: message)
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
