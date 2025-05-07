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

import PackageGraph
import PackageModel

import SPMBuildCore
import SwiftFixIt

import var TSCBasic.stdoutStream

struct MigrateOptions: ParsableArguments {
    @Option(
        name: .customLong("targets"),
        help: "The targets to migrate to specified set of features."
    )
    var _targets: String?

    var targets: Set<String>? {
        self._targets.flatMap { Set($0.components(separatedBy: ",")) }
    }

    @Option(
        name: .customLong("to-feature"),
        parsing: .unconditionalSingleValue,
        help: "The Swift language upcoming/experimental feature to migrate to."
    )
    var features: [String]
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

            let buildSystem = try await createBuildSystem(
                swiftCommandState,
                features: features
            )

            // Next, let's build all of the individual targets or the
            // whole project to get diagnostic files.

            print("> Starting the build.")
            if let targets = self.options.targets {
                for target in targets {
                    try await buildSystem.build(subset: .target(target))
                }
            } else {
                try await buildSystem.build(subset: .allIncludingTests)
            }

            // Determine all of the targets we need up update.
            let buildPlan = try buildSystem.buildPlan

            var modules: [any ModuleBuildDescription] = []
            if let targets = self.options.targets {
                for buildDescription in buildPlan.buildModules where targets.contains(buildDescription.module.name) {
                    modules.append(buildDescription)
                }
            } else {
                let graph = try await buildSystem.getPackageGraph()
                for buildDescription in buildPlan.buildModules
                    where graph.isRootPackage(buildDescription.package) && buildDescription.module.type != .plugin
                {
                    modules.append(buildDescription)
                }
            }

            // If the build suceeded, let's extract all of the diagnostic
            // files from build plan and feed them to the fix-it tool.

            print("> Applying fix-its.")
            for module in modules {
                let fixit = try SwiftFixIt(
                    diagnosticFiles: module.diagnosticFiles,
                    fileSystem: swiftCommandState.fileSystem
                )
                try fixit.applyFixIts()
            }

            // Once the fix-its were applied, it's time to update the
            // manifest with newly adopted feature settings.

            print("> Updating manifest.")
            for module in modules.map(\.module) {
                print("> Adding feature(s) to '\(module.name)'.")
                for feature in features {
                    self.updateManifest(
                        for: module.name,
                        add: feature,
                        using: swiftCommandState
                    )
                }
            }
        }

        private func createBuildSystem(
            _ swiftCommandState: SwiftCommandState,
            features: [SwiftCompilerFeature]
        ) async throws -> BuildSystem {
            let toolsBuildParameters = try swiftCommandState.toolsBuildParameters
            var destinationBuildParameters = try swiftCommandState.productsBuildParameters

            // Inject feature settings as flags. This is safe and not as invasive
            // as trying to update manifest because in adoption mode the features
            // can only produce warnings.
            for feature in features {
                destinationBuildParameters.flags.swiftCompilerFlags.append(contentsOf: [
                    "-Xfrontend",
                    "-enable-\(feature.upcoming ? "upcoming" : "experimental")-feature",
                    "-Xfrontend",
                    "\(feature.name):migrate",
                ])
            }

            return try await swiftCommandState.createBuildSystem(
                traitConfiguration: .init(),
                productsBuildParameters: destinationBuildParameters,
                toolsBuildParameters: toolsBuildParameters,
                // command result output goes on stdout
                // ie "swift build" should output to stdout
                outputStream: TSCBasic.stdoutStream
            )
        }

        private func updateManifest(
            for target: String,
            add feature: SwiftCompilerFeature,
            using swiftCommandState: SwiftCommandState
        ) {
            typealias SwiftSetting = SwiftPackageCommand.AddSetting.SwiftSetting

            let setting: (SwiftSetting, String) = switch feature {
            case .upcoming(name: let name, migratable: _, enabledIn: _):
                (.upcomingFeature, "\(name)")
            case .experimental(name: let name, migratable: _):
                (.experimentalFeature, "\(name)")
            }

            do {
                try SwiftPackageCommand.AddSetting.editSwiftSettings(
                    of: target,
                    using: swiftCommandState,
                    [setting]
                )
            } catch {
                print(
                    "! Couldn't update manifest due to - \(error); Please add '.enable\(feature.upcoming ? "Upcoming" : "Experimental")Feature(\"\(feature.name)\")' to target '\(target)' settings manually."
                )
            }
        }

        public init() {}
    }
}
