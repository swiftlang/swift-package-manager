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
import struct LLBuildManifest.PlaygroundRunnerTool

@_spi(SwiftPMInternal)
import struct PackageGraph.ResolvedModule

import struct PackageGraph.ResolvedProduct
import struct PackageModel.Sources
import class PackageModel.SwiftModule
import struct SPMBuildCore.BuildParameters
import protocol TSCBasic.FileSystem

extension BuildPlan {
    /// Creates and returns a module build description for a synthesized Playground runner executable target.
    static func makeDerivedPlaygroundRunnerTargets(
        playgroundRunnerProductBuildDescription: ProductBuildDescription,
        destinationBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        shouldDisableSandbox: Bool,
        _ fileSystem: FileSystem,
        _ observabilityScope: ObservabilityScope
    ) throws -> [(product: ResolvedProduct, playgroundRunnerTargetBuildDescription: SwiftModuleBuildDescription)] {
        let playgroundProduct = playgroundRunnerProductBuildDescription.product
        guard let playgroundRunnerTarget = playgroundProduct.modules.first(where: { $0.underlying.isPlaygroundRunner }) else {
            return []
        }

        let targetName = playgroundRunnerTarget.name

        // Playground runner target builds from a derived source file (written out by a playground runner build cmd)
        let derivedDir = playgroundRunnerProductBuildDescription.buildParameters.buildPath.appending(components: "\(targetName).derived")
        let mainFile = derivedDir.appending(component: PlaygroundRunnerTool.mainFileName)

        let target = SwiftModule(
            name: targetName,
            type: .executable,
            path: .root,
            sources: Sources(paths: [mainFile], root: derivedDir),
            dependencies: playgroundRunnerTarget.underlying.dependencies, // copy template target's dependencies
            packageAccess: true, // playground target is allowed access to package decls
            usesUnsafeFlags: false,
            implicit: true, // implicitly created for swift play
            isPlaygroundRunner: true
        )

        let resolvedTarget = ResolvedModule(
            packageIdentity: playgroundProduct.packageIdentity,
            underlying: target,
            dependencies: playgroundRunnerTarget.dependencies, // copy template target's dependencies
            defaultLocalization: playgroundProduct.defaultLocalization,
            supportedPlatforms: playgroundProduct.supportedPlatforms,
            platformVersionProvider: playgroundProduct.platformVersionProvider
        )

        let targetBuildDescription = try SwiftModuleBuildDescription(
            package: playgroundRunnerProductBuildDescription.package,
            target: resolvedTarget,
            toolsVersion: playgroundRunnerProductBuildDescription.package.manifest.toolsVersion,
            buildParameters: playgroundRunnerProductBuildDescription.buildParameters,
            macroBuildParameters: toolsBuildParameters,
            testTargetRole: nil,
            shouldDisableSandbox: shouldDisableSandbox,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            isPlaygroundRunnerTarget: true
        )

        return [(playgroundProduct, targetBuildDescription)]
    }
}
