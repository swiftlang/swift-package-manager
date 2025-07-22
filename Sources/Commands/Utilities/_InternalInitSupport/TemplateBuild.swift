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
import SPMBuildCore
import TSCBasic
import TSCUtility

/// A utility for building Swift packages using the SwiftPM build system.
///
/// `TemplateBuildSupport` encapsulates the logic needed to initialize the
/// SwiftPM build system and perform a build operation based on a specific
/// command configuration and workspace context.

enum TemplateBuildSupport {
    /// Builds a Swift package using the given command state, options, and working directory.
    ///
    /// This method performs the following steps:
    /// 1. Initializes a temporary workspace, optionally switching to a user-specified package directory.
    /// 2. Creates a build system with the specified configuration, including product, traits, and build parameters.
    /// 3. Resolves the build subset (e.g., targets or products to build).
    /// 4. Executes the build within the workspace.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The current Swift command state, containing context such as the workspace and
    /// diagnostics.
    ///   - buildOptions: Options used to configure what and how to build, including the product and traits.
    ///   - globalOptions: Global configuration such as the package directory and logging verbosity.
    ///   - cwd: The current working directory to use if no package directory is explicitly provided.
    ///
    /// - Throws:
    ///   - `ExitCode.failure` if no valid build subset can be resolved or if the build fails due to diagnostics.
    ///   - Any other errors thrown during workspace setup or build system creation.
    static func build(
        swiftCommandState: SwiftCommandState,
        buildOptions: BuildCommandOptions,
        globalOptions: GlobalOptions,
        cwd: Basics.AbsolutePath,
        transitiveFolder: Basics.AbsolutePath? = nil
    ) async throws {


        let buildSystem = try await swiftCommandState
            .withTemporaryWorkspace(switchingTo: transitiveFolder ?? globalOptions.locations.packageDirectory ?? cwd) { _, _ in

                try await swiftCommandState.createBuildSystem(
                    explicitProduct: buildOptions.product,
                    traitConfiguration: .init(traitOptions: buildOptions.traits),
                    shouldLinkStaticSwiftStdlib: buildOptions.shouldLinkStaticSwiftStdlib,
                    productsBuildParameters: swiftCommandState.productsBuildParameters,
                    toolsBuildParameters: swiftCommandState.toolsBuildParameters,
                    outputStream: TSCBasic.stdoutStream
                )
            }

        guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
            throw ExitCode.failure
        }



        try await swiftCommandState
            .withTemporaryWorkspace(switchingTo: transitiveFolder ?? globalOptions.locations.packageDirectory ?? cwd) { _, _ in
                do {
                    try await buildSystem.build(subset: subset)
                } catch _ as Diagnostics {
                    throw ExitCode.failure
                }
            }
    }

    static func buildForTesting(
        swiftCommandState: SwiftCommandState,
        buildOptions: BuildCommandOptions,
        testingFolder: Basics.AbsolutePath
    ) async throws {

        var productsBuildParameters = try swiftCommandState.productsBuildParameters
        var toolsBuildParameters = try swiftCommandState.toolsBuildParameters

        if buildOptions.enableCodeCoverage {
            productsBuildParameters.testingParameters.enableCodeCoverage = true
            toolsBuildParameters.testingParameters.enableCodeCoverage = true
        }

        if buildOptions.printPIFManifestGraphviz {
            productsBuildParameters.printPIFManifestGraphviz = true
            toolsBuildParameters.printPIFManifestGraphviz = true
        }


        let buildSystem = try await swiftCommandState
            .withTemporaryWorkspace(switchingTo: testingFolder) { _, _ in
                try await swiftCommandState.createBuildSystem(
                    explicitProduct: buildOptions.product,
                    traitConfiguration: .init(traitOptions: buildOptions.traits),
                    shouldLinkStaticSwiftStdlib: buildOptions.shouldLinkStaticSwiftStdlib,
                    productsBuildParameters: swiftCommandState.productsBuildParameters,
                    toolsBuildParameters: swiftCommandState.toolsBuildParameters,
                    outputStream: TSCBasic.stdoutStream
                )
            }

        guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
            throw ExitCode.failure
        }

        try await swiftCommandState
            .withTemporaryWorkspace(switchingTo: testingFolder) { _, _ in
                do {
                    try await buildSystem.build(subset: subset)
                } catch _ as Diagnostics {
                    throw ExitCode.failure
                }
            }
    }

}
