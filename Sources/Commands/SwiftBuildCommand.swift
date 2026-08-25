//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics

import Build

@_spi(SwiftPMInternal)
import CoreCommands

import PackageGraph

import SPMBuildCore
import XCBuildSupport
import SwiftBuildSupport
import struct PackageModel.PackageIdentity

import class Basics.AsyncProcess
import var TSCBasic.stdoutStream

import enum TSCUtility.Diagnostics
import func TSCUtility.getClangVersion
import struct TSCUtility.Version

import Foundation
import SBOMModel
import Workspace

extension BuildSubset {
    var argumentName: String {
        switch self {
        case .allExcludingTests:
            fatalError("no corresponding argument")
        case .allIncludingTests:
            return "--build-tests"
        case .product:
            return "--product"
        case .target:
            return "--target"
        case .workspaceMember:
            fatalError("no corresponding argument")
        }
    }
}

struct BuildCommandOptions: ParsableArguments {
    /// Pure decision logic for translating command-line options + Case A
    /// focus + `--package` selector into a `BuildSubset`. Extracted for
    /// direct unit testing; the instance method
    /// `buildSubset(observabilityScope:workspaceMemberFocus:availableMemberIdentities:)`
    /// simply forwards its stored fields to this helper.
    ///
    /// Ordering:
    /// 1. `--product` and `--target` compose with `--package` — the
    ///    named artifact is scoped to the selected member.
    /// 2. `--product`, `--target`, and `--build-tests` are mutually
    ///    exclusive with each other. `--package` is compatible with
    ///    any single one.
    /// 3. `--package` supplied without a workspace: hard error.
    ///    `--package` naming an unknown identity: hard error listing
    ///    known identities.
    /// 4. When only `--package` is set → `.workspaceMember(<id>)`.
    /// 5. When no explicit override and no `--package` but a
    ///    `workspaceMemberFocus` is set → `.workspaceMember(focus)`.
    /// 6. Fallback → `.allExcludingTests`.
    static func computeBuildSubset(
        product: String?,
        target: String?,
        buildTests: Bool,
        selectedPackage: PackageIdentity? = nil,
        workspaceMemberFocus: PackageIdentity?,
        availableMemberIdentities: Set<PackageIdentity>? = nil,
        observabilityScope: ObservabilityScope,
    ) -> BuildSubset? {
        // Resolve `--package` first: emits its own errors and either
        // returns a validated PackageIdentity or nil to abort.
        let resolvedPackage: PackageIdentity?
        if let selectedPackage {
            guard let availableMemberIdentities else {
                observabilityScope.emit(
                    .packageSelectorRequiresWorkspace(requested: selectedPackage),
                )
                return nil
            }
            guard availableMemberIdentities.contains(selectedPackage) else {
                observabilityScope.emit(
                    .unknownWorkspaceMember(
                        requested: selectedPackage,
                        known: availableMemberIdentities,
                    ),
                )
                return nil
            }
            resolvedPackage = selectedPackage
        } else {
            resolvedPackage = nil
        }

        // Mutual exclusion applies across `--product`, `--target`,
        // `--build-tests`; `--package` composes with (at most one of)
        // these to scope the lookup.
        var allSubsets: [BuildSubset] = []

        if let product {
            allSubsets.append(.product(product, for: nil, package: resolvedPackage))
        }

        if let target {
            allSubsets.append(.target(target, for: nil, package: resolvedPackage))
        }

        if buildTests {
            allSubsets.append(.allIncludingTests(package: resolvedPackage))
        }

        guard allSubsets.count < 2 else {
            observabilityScope.emit(
                .mutuallyExclusiveArgumentsError(arguments: allSubsets.map { $0.argumentName }),
            )
            return nil
        }

        if let explicit = allSubsets.first {
            return explicit
        }

        if let resolvedPackage {
            return .workspaceMember(resolvedPackage)
        }

        if let workspaceMemberFocus {
            return .workspaceMember(workspaceMemberFocus)
        }

        return .allExcludingTests()
    }

    /// Returns the build subset specified with the options.
    func buildSubset(
        observabilityScope: ObservabilityScope,
        workspaceMemberFocus: PackageIdentity? = nil,
        availableMemberIdentities: Set<PackageIdentity>? = nil,
    ) -> BuildSubset? {
        Self.computeBuildSubset(
            product: self.product,
            target: self.target,
            buildTests: self.buildTests,
            selectedPackage: self.selectedPackage,
            workspaceMemberFocus: workspaceMemberFocus,
            availableMemberIdentities: availableMemberIdentities,
            observabilityScope: observabilityScope,
        )
    }

    /// If the test should be built.
    @Flag(help: "Build both source and test targets.")
    var buildTests: Bool = false

    /// Whether to enable code coverage.
    @Flag(
        name: [
            .customLong("coverage"),
        ],
        inversion: .prefixedEnableDisable,
        help: "Enable code coverage.",
    )
    var _enableCoverage: Bool = false

    /// Whether to enable code coverage. (deprecated options)
    @Flag(
        name: [
            .customLong("code-coverage"),
        ],
        inversion: .prefixedEnableDisable,
        help: "Enable code coverage. (deprecated. use '--enable-coverage/--disable-coverage' instead)",
    )
    var _enableCodeCoverageDeprecated: Bool?

    var enableCodeCoverage: Bool {
        return self._enableCoverage || (self._enableCodeCoverageDeprecated ?? false)
    }

    /// Determines whether the build command prints the binary output path.
    @Flag(name: .customLong("show-bin-path"), help: "Print the binary output path.")
    var shouldPrintBinPath: Bool = false

    /// Whether to output a graphviz file visualization of the combined job graph for all targets
    @Flag(name: .customLong("print-manifest-job-graph"),
          help: "Write the command graph for the build manifest as a Graphviz file.")
    var printManifestGraphviz: Bool = false

    /// Whether to output a graphviz file visualization of the PIF JSON sent to Swift Build.
    @Flag(name: .customLong("print-pif-manifest-graph"),
          help: "Write the PIF JSON sent to Swift Build as a Graphviz file.")
    var printPIFManifestGraphviz: Bool = false

    /// Specific target to build.
    @Option(help: "Build the specified target.")
    var target: String?

    /// Specific product to build.
    @Option(help: "Build the specified product.")
    var product: String?

    /// Select a specific workspace member by identity. Requires a
    /// `Workspace.swift` to be discoverable; scopes the build to that
    /// member's products (or, when combined with `--product` /
    /// `--target`, scopes the lookup to that member).
    @Option(
        name: .customLong("package"),
        help: "Select a specific workspace member by identity.",
    )
    var selectedPackage: PackageIdentity?

    /// Testing library options.
    ///
    /// These options are no longer used but are needed by older versions of the
    /// Swift VSCode plugin. They will be removed in a future update.
    @OptionGroup(visibility: .private)
    var testLibraryOptions: TestLibraryOptions

    /// Determines whether the binary should statically link the Swift stdlib.
    @Flag(name: .customLong("static-swift-stdlib"), inversion: .prefixedNo, help: "Determines whether Swift stdlib links statically.")
    public var shouldLinkStaticSwiftStdlib: Bool = false

    @OptionGroup(title: "Software Bill of Materials (SBOM)")
    var sbom: SBOMOptions
}

/// swift-build command namespace
public struct SwiftBuildCommand: AsyncSwiftCommand {
    public static var configuration = CommandConfiguration(
        commandName: "build",
        _superCommandName: "swift",
        abstract: "Build sources into binary products.",
        discussion: "SEE ALSO: swift run, swift package, swift test",
        version: SwiftVersion.current.completeDisplayString,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    public var globalOptions: GlobalOptions

    @OptionGroup()
    var options: BuildCommandOptions

    public func run(_ swiftCommandState: SwiftCommandState) async throws {

        if options._enableCodeCoverageDeprecated != nil {
            swiftCommandState.observabilityScope.emit(Basics.Diagnostic.deprecatedEnableDisableCoverage)
        }

        if options.shouldPrintBinPath {
            let buildSystem = try await swiftCommandState.createBuildSystem()
            return try await print(buildSystem.buildProductsPath(for: swiftCommandState.productsBuildParameters).description)
        }

        if options.printManifestGraphviz {
            // FIXME: Doesn't seem ideal that we need an explicit build operation, but this concretely uses the `LLBuildManifest`.
            guard let buildOperation = try await swiftCommandState.createBuildSystem(
                explicitBuildSystem: .native,
            ) as? BuildOperation else {
                throw StringError("asked for native build system but did not get it")
            }
            let buildManifest = try await buildOperation.getBuildManifest()
            var serializer = DOTManifestSerializer(manifest: buildManifest)
            // Print to stdout.
            let outputStream = stdoutStream
            serializer.writeDOT(to: outputStream)
            outputStream.flush()
            return
        }

        // Eagerly discover the workspace (if any) so that
        // `currentWorkspaceMemberFocus` is populated before the build
        // subset is computed. Without this, `getWorkspaceRoot()` would
        // only run when the build system lazily loads root manifests —
        // long after `options.buildSubset(workspaceMemberFocus:)` has
        // already been evaluated against a nil focus.
        _ = try await swiftCommandState.getWorkspaceRoot()

        guard let subset = options.buildSubset(
            observabilityScope: swiftCommandState.observabilityScope,
            workspaceMemberFocus: swiftCommandState.currentWorkspaceMemberFocus,
            availableMemberIdentities: swiftCommandState.currentWorkspaceMemberIdentities,
        ) else {
            throw ExitCode.failure
        }

        var productsBuildParameters = try swiftCommandState.productsBuildParameters
        var toolsBuildParameters = try swiftCommandState.toolsBuildParameters

        if self.options.enableCodeCoverage {
            productsBuildParameters.testingParameters.enableCodeCoverage = true
            toolsBuildParameters.testingParameters.enableCodeCoverage = true
        }

        if self.options.printPIFManifestGraphviz {
            productsBuildParameters.printPIFManifestGraphviz = true
            toolsBuildParameters.printPIFManifestGraphviz = true
        }

        if swiftCommandState.options.build.enableCodesizeProfile {
            var driverParameters = productsBuildParameters.driverParameters
            driverParameters.codesizeProfileEnabled = true
            driverParameters.emitSILFiles = true
            driverParameters.emitIRFiles = true
            driverParameters.emitOptimizationRecord = true

            if let outputDir = swiftCommandState.options.build.codesizeProfileOutputDirectory {
                let outputPath = try AbsolutePath(validating: outputDir, relativeTo: swiftCommandState.originalWorkingDirectory)
                driverParameters.silOutputDirectory = outputPath
                driverParameters.irOutputDirectory = outputPath
                driverParameters.optimizationRecordDirectory = outputPath
            }
            productsBuildParameters.driverParameters = driverParameters
        }

        do {
            try await build(
                swiftCommandState,
                subset: subset,
                productsBuildParameters: productsBuildParameters,
                toolsBuildParameters: toolsBuildParameters,
            )
        } catch SwiftBuildSupport.PIFGenerationError.printedPIFManifestGraphviz {
            throw ExitCode.success
        } catch _ as Diagnostics {
            throw ExitCode.failure
        }
    }

    private func build(
        _ swiftCommandState: SwiftCommandState,
        subset: BuildSubset,
        productsBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
    ) async throws {
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitProduct: options.product,
            shouldLinkStaticSwiftStdlib: options.shouldLinkStaticSwiftStdlib,
            productsBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            // command result output goes on stdout
            // ie "swift build" should output to stdout
            outputStream: TSCBasic.stdoutStream
        )
        let buildResult = try await buildSystem.build(subset: subset, buildOutputs: try await getBuildOutputs())
        try await processBuildResult(swiftCommandState, buildSystem: buildSystem, buildResult: buildResult)
    }

    private func getBuildOutputs() async throws -> [BuildOutput] {
        return try self.options.sbom.sbomSpecs.isEmpty ? [] : [.dependencyGraph]
    }

    private func processBuildResult(
        _ swiftCommandState: SwiftCommandState,
        buildSystem: any BuildSystem,
        buildResult: BuildResult) async throws {
        if try !self.options.sbom.sbomSpecs.isEmpty {
            try await generateSBOMs(swiftCommandState, buildSystem, buildResult)
        }
    }

    private func generateSBOMs(
        _ swiftCommandState: SwiftCommandState,
        _ buildSystem: any BuildSystem,
        _ buildResult: BuildResult) async throws {
        do {
            guard try self.options.sbom.sbomSpecs.isEmpty || options.target == nil else {
                throw SBOMModel.SBOMCommandError.targetFlagNotSupported
            }
            let workspace = try swiftCommandState.getActiveWorkspace()
            let packageGraph = try await buildSystem.getPackageGraph()
            let resolvedPackagesStore = try workspace.resolvedPackagesStore.load()
            let input = SBOMInput(
                modulesGraph: packageGraph,
                dependencyGraph: buildResult.dependencyGraph,
                store: resolvedPackagesStore,
                filter: try self.options.sbom.sbomFilter,
                product: options.product,
                specs: try self.options.sbom.sbomSpecs,
                dir: await SBOMCreator.resolveSBOMDirectory(from: self.options.sbom.sbomDirectory, withDefault: try await buildSystem.buildProductsPath(for: swiftCommandState.productsBuildParameters)),
                observabilityScope: swiftCommandState.observabilityScope
            )

            let creator = SBOMCreator(input: input)
            try await creator.createSBOMsWithLogging()
            if self.globalOptions.build.buildSystem != .swiftbuild {
                swiftCommandState.observabilityScope.emit(warning: "generating SBOM(s) without `--build-system swiftbuild` flag creates SBOM(s) without build-time conditionals.")
            }
        } catch {
            if self.options.sbom.sbomWarningOnly {
                swiftCommandState.observabilityScope.emit(warning: "SBOM generation failed: \(error.localizedDescription)")
            } else {
                throw error
            }
        }
    }

    public init() {}
}

public extension _SwiftCommand {
    func buildSystemProvider(_ swiftCommandState: SwiftCommandState) throws -> BuildSystemProvider {
        swiftCommandState.defaultBuildSystemProvider
    }
}
