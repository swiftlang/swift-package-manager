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
import SBOMModel
import SPMBuildCore
import Workspace

extension SwiftPackageCommand {
    
    
    struct GenerateSbom: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate a Software Bill of Materials (SBOM).")

        @OptionGroup()
        var globalOptions: GlobalOptions

        @Option(help: "The product to generate an SBOM for.")
        var product: String?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard !globalOptions.sbom.sbomSpecs.isEmpty else {
                throw SBOMModel.SBOMCommandError.noSpecArg
            }
            
            swiftCommandState.observabilityScope.emit(warning: "`generate-sbom` subcommand creates SBOM(s) based on modules graph only")

            let workspace = try swiftCommandState.getActiveWorkspace()
            let packageGraph = try await workspace.loadPackageGraph(
                rootInput: swiftCommandState.getWorkspaceRoot(),
                explicitProduct: self.product,
                forceResolvedVersions: self.globalOptions.resolver.forceResolvedVersions,
                observabilityScope: swiftCommandState.observabilityScope
            )
            let resolvedPackagesStore = try workspace.resolvedPackagesStore.load()

            let input = SBOMInput(
                modulesGraph: packageGraph,
                dependencyGraph: nil,
                store: resolvedPackagesStore,
                filter: self.globalOptions.sbom.sbomFilter,
                product: self.product,
                specs: self.globalOptions.sbom.sbomSpecs,
                dir: await SBOMCreator.resolveSBOMDirectory(from: self.globalOptions.sbom.sbomDirectory, withDefault: try swiftCommandState.productsBuildParameters.buildPath)
            )

            print("Creating SBOMs...")
            let sbomStartTime = ContinuousClock.Instant.now
            let creator = SBOMCreator(input: input)
            let sbomPaths = try await creator.createSBOMs()
            let duration = ContinuousClock.Instant.now - sbomStartTime
            let formattedDuration = duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2, rounded: .up)))
            for sbomPath in sbomPaths {
                // TODO echeng3805 should this be using observabilityScope?
                print("- created SBOM at \(sbomPath.pathString)")
            }
            print("SBOMs created  (\(formattedDuration))")
        }
    }
}
