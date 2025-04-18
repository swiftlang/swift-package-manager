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

import class Basics.ObservabilityScope
import struct LLBuildManifest.PlaygroundEntryPointTool

@_spi(SwiftPMInternal)
import struct PackageGraph.ResolvedModule

import struct PackageGraph.ResolvedProduct
import struct PackageModel.Sources
import class PackageModel.SwiftModule
import struct SPMBuildCore.BuildParameters
import protocol TSCBasic.FileSystem

extension BuildPlan {
    static func makeDerivedPlaygroundTargets(
        playgroundProducts: [ProductBuildDescription],
        destinationBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        shouldDisableSandbox: Bool,
        _ fileSystem: FileSystem,
        _ observabilityScope: ObservabilityScope
    ) throws -> [(product: ResolvedProduct, entryPointTargetBuildDescription: SwiftModuleBuildDescription)] {
        var result: [(ResolvedProduct, SwiftModuleBuildDescription)] = []
        for playgroundBuildDescription in playgroundProducts {
            let playgroundProduct = playgroundBuildDescription.product
            let package = playgroundBuildDescription.package

            let toolsVersion = package.manifest.toolsVersion

            /// Generates a synthesized playground entry point target, consisting of a single "main" file which handles the playground entry point.
            func generateSynthesizedPlaygroundEntryPointTarget() throws -> SwiftModuleBuildDescription {
                let entryPointDerivedDir = destinationBuildParameters.buildPath.appending(components: "\(playgroundProduct.name).derived")
                let entryPointMainFile = entryPointDerivedDir.appending(component: PlaygroundEntryPointTool.mainFileName)
                let entryPointSources = Sources(paths: [entryPointMainFile], root: entryPointDerivedDir)

                let entryPointTarget = SwiftModule(
                    name: playgroundProduct.name,
                    type: .library,
                    path: .root,
                    sources: entryPointSources,
                    dependencies: playgroundProduct.underlying.modules.map { .module($0, conditions: []) },
                    packageAccess: true, // playground target is allowed access to package decls
                    usesUnsafeFlags: false
                )
                let entryPointResolvedTarget = ResolvedModule(
                    packageIdentity: playgroundProduct.packageIdentity,
                    underlying: entryPointTarget,
                    dependencies: playgroundProduct.modules.map { .module($0, conditions: []) },
                    defaultLocalization: playgroundProduct.defaultLocalization,
                    supportedPlatforms: playgroundProduct.supportedPlatforms,
                    platformVersionProvider: playgroundProduct.platformVersionProvider
                )

                return try SwiftModuleBuildDescription(
                    package: package,
                    target: entryPointResolvedTarget,
                    toolsVersion: toolsVersion,
                    buildParameters: playgroundBuildDescription.buildParameters,
                    macroBuildParameters: toolsBuildParameters,
                    testTargetRole: nil,
                    shouldDisableSandbox: shouldDisableSandbox,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope,
                    isPlaygroundTarget: true
                )
            }
            
            // Synthesize a playground entry point target, declaring a dependency on the test discovery targets.
            let entryPointTargetBuildDescription = try generateSynthesizedPlaygroundEntryPointTarget()
            result.append((playgroundProduct, entryPointTargetBuildDescription))
        }

        return result
    }
}
