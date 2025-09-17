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

/// A utility for building Swift packages templates using the SwiftPM build system.
///
/// `TemplateBuildSupport` encapsulates the logic needed to initialize the
/// SwiftPM build system and perform a build operation based on a specific
/// command configuration and workspace context.

enum TemplateBuildSupport {

    /// Builds a Swift package using the given command state, options, and working directory.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The current Swift command state, containing context such as the workspace and diagnostics.
    ///   - buildOptions: Options used to configure what and how to build, including the product and traits.
    ///   - globalOptions: Global configuration such as the package directory and logging verbosity.
    ///   - cwd: The current working directory to use if no package directory is explicitly provided.
    ///   - transitiveFolder: Optional override for the package directory.
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
        let packageRoot = transitiveFolder ?? globalOptions.locations.packageDirectory ?? cwd

        let buildSystem = try await makeBuildSystem(
            swiftCommandState: swiftCommandState,
            folder: packageRoot,
            buildOptions: buildOptions
        )

        guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
            throw ExitCode.failure
        }

        try await swiftCommandState.withTemporaryWorkspace(switchingTo: packageRoot) { _, _ in
            do {
                try await buildSystem.build(subset: subset, buildOutputs: [.buildPlan])
            } catch {
                throw ExitCode.failure
            }
        }
    }

    /// Builds a Swift package for testing, applying code coverage and PIF graph options.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The current Swift command state.
    ///   - buildOptions: Options used to configure the build.
    ///   - testingFolder: The path to the folder containing the testable package.
    ///
    /// - Throws: Errors related to build preparation or diagnostics.
    static func buildForTesting(
        swiftCommandState: SwiftCommandState,
        buildOptions: BuildCommandOptions,
        testingFolder: Basics.AbsolutePath
    ) async throws {
        let buildSystem = try await makeBuildSystem(
            swiftCommandState: swiftCommandState,
            folder: testingFolder,
            buildOptions: buildOptions,
            forTesting: true
        )

        guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
            throw ExitCode.failure
        }

        try await swiftCommandState.withTemporaryWorkspace(switchingTo: testingFolder) { _, _ in
            do {
                try await buildSystem.build(subset: subset, buildOutputs: [.buildPlan])
            } catch let diagnostics as Diagnostics {
                throw ExitCode.failure
            }
        }
    }

    /// Internal helper to create a `BuildSystem` with appropriate parameters.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The active command context.
    ///   - folder: The directory to switch into for workspace operations.
    ///   - buildOptions: Build configuration options.
    ///   - forTesting: Whether to apply test-specific parameters (like code coverage).
    ///
    /// - Returns: A configured `BuildSystem` instance ready to build.
    private static func makeBuildSystem(
        swiftCommandState: SwiftCommandState,
        folder: Basics.AbsolutePath,
        buildOptions: BuildCommandOptions,
        forTesting: Bool = false
    ) async throws -> BuildSystem {
        var productsParams = try swiftCommandState.productsBuildParameters
        var toolsParams = try swiftCommandState.toolsBuildParameters

        if forTesting {
            if buildOptions.enableCodeCoverage {
                productsParams.testingParameters.enableCodeCoverage = true
                toolsParams.testingParameters.enableCodeCoverage = true
            }

            if buildOptions.printPIFManifestGraphviz {
                productsParams.printPIFManifestGraphviz = true
                toolsParams.printPIFManifestGraphviz = true
            }
        }

        return try await swiftCommandState.withTemporaryWorkspace(switchingTo: folder) { _, _ in
            try await swiftCommandState.createBuildSystem(
                explicitProduct: buildOptions.product,
                shouldLinkStaticSwiftStdlib: buildOptions.shouldLinkStaticSwiftStdlib,
                productsBuildParameters: productsParams,
                toolsBuildParameters: toolsParams,
                outputStream: TSCBasic.stdoutStream
            )
        }
    }
}
