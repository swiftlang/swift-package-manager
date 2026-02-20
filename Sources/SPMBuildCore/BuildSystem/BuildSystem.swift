//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageGraph

import enum PackageModel.TraitConfiguration

import protocol TSCBasic.OutputByteStream

/// An enum representing what subset of the package to build.
public enum BuildSubset {
    /// Represents the subset of all products and non-test targets.
    case allExcludingTests

    /// Represents the subset of all products and targets.
    case allIncludingTests

    /// Represents a specific product. Allows to set a specific
    /// destination if it's known.
    case product(String, for: BuildParameters.Destination? = .none)

    /// Represents a specific target. Allows to set a specific
    /// destination if it's known.
    case target(String, for: BuildParameters.Destination? = .none)
}

/// Represents possible extra build outputs for a build. Some build systems
/// can produce certain extra outputs in the process of building. Not all
/// build systems can produce all possible build outputs. Check the build
/// result for indication that the output was produced.
public enum BuildOutput: Equatable {
    public enum SymbolGraphAccessLevel: String {
        case `private`, `fileprivate`, `internal`, `package`, `public`, `open`
    }
    public struct SymbolGraphOptions: Equatable {
        public var prettyPrint: Bool
        public var minimumAccessLevel: SymbolGraphAccessLevel
        public var includeInheritedDocs: Bool
        public var includeSynthesized: Bool
        public var includeSPI: Bool
        public var emitExtensionBlocks: Bool

        public init(
            prettyPrint: Bool = false,
            minimumAccessLevel: SymbolGraphAccessLevel,
            includeInheritedDocs: Bool,
            includeSynthesized: Bool,
            includeSPI: Bool,
            emitExtensionBlocks: Bool
        ) {
            self.prettyPrint = prettyPrint
            self.minimumAccessLevel = minimumAccessLevel
            self.includeInheritedDocs = includeInheritedDocs
            self.includeSynthesized = includeSynthesized
            self.includeSPI = includeSPI
            self.emitExtensionBlocks = emitExtensionBlocks
        }
    }

    case symbolGraph(SymbolGraphOptions)
    case buildPlan
    case replArguments
    case builtArtifacts
}

/// A protocol that represents a build system used by SwiftPM for all build operations. This allows factoring out the
/// implementation details between SwiftPM's `BuildOperation` and the Swift Build backed `SwiftBuildSystem`.
public protocol BuildSystem: Cancellable {

    /// The delegate used by the build system.
    var delegate: BuildSystemDelegate? { get }

    /// The test products that this build system will build.
    var builtTestProducts: [BuiltTestProduct] { get async }

    /// Returns the package graph used by the build system.
    func getPackageGraph() async throws -> ModulesGraph

    /// Builds a subset of the package graph.
    /// - Parameters:
    ///   - buildOutputs: Additional build outputs requested from the build system.
    /// - Returns: A build result with details about requested build and outputs.
    @discardableResult
    func build(subset: BuildSubset, buildOutputs: [BuildOutput]) async throws -> BuildResult

    var hasIntegratedAPIDigesterSupport: Bool { get }

    func generatePIF(preserveStructure: Bool) async throws -> String
}

extension BuildSystem {
    /// Builds the default subset: all targets excluding tests with no extra build outputs.
    @discardableResult
    public func build() async throws -> BuildResult {
        try await build(subset: .allExcludingTests, buildOutputs: [])
    }
}

public struct SymbolGraphResult {
    public init(outputLocationForTarget: @escaping (String, BuildParameters) -> [String]) {
        self.outputLocationForTarget = outputLocationForTarget
    }

    /// Find the build path relative location of the symbol graph output directory
    /// for a provided target and build parameters. Note that the directory may not
    /// exist when the target doesn't have any symbol graph output, as one example.
    public let outputLocationForTarget: (String, BuildParameters) -> [String]
}

public typealias CLIArguments = [String]

public struct BuildResult {
    package init(
        serializedDiagnosticPathsByTargetName: Result<[String: [AbsolutePath]], Error>,
        symbolGraph: SymbolGraphResult? = nil,
        buildPlan: BuildPlan? = nil,
        replArguments: CLIArguments?,
        builtArtifacts: [(String, PluginInvocationBuildResult.BuiltArtifact)]? = nil
    ) {
        self.serializedDiagnosticPathsByTargetName = serializedDiagnosticPathsByTargetName
        self.symbolGraph = symbolGraph
        self.buildPlan = buildPlan
        self.replArguments = replArguments
        self.builtArtifacts = builtArtifacts
    }

    public let replArguments: CLIArguments?
    public let symbolGraph: SymbolGraphResult?
    public let buildPlan: BuildPlan?

    public var serializedDiagnosticPathsByTargetName: Result<[String: [AbsolutePath]], Error>
    public var builtArtifacts: [(String, PluginInvocationBuildResult.BuiltArtifact)]?
}

public protocol ProductBuildDescription {
    /// The reference to the product.
    var package: ResolvedPackage { get }

    /// The reference to the product.
    var product: ResolvedProduct { get }

    /// The build parameters.
    var buildParameters: BuildParameters { get }
}

extension ProductBuildDescription {
    /// The path to the product binary produced.
    public var binaryPath: AbsolutePath {
        get throws {
            try self.buildParameters.binaryPath(for: product)
        }
    }
}

public protocol ModuleBuildDescription {
    /// The package the module belongs to.
    var package: ResolvedPackage { get }

    /// The underlying module this description is for.
    var module: ResolvedModule { get }

    /// The build parameters.
    var buildParameters: BuildParameters { get }

    /// The diagnostic file locations for all the source files
    /// associated with this module.
    var diagnosticFiles: [AbsolutePath] { get }

    /// FIXME: This shouldn't be necessary and ideally
    /// there should be a way to ask build system to
    /// introduce these arguments while building for symbol
    /// graph extraction.
    func symbolGraphExtractArguments() throws -> [String]
}

public protocol BuildPlan {
    /// Parameters used when building end products for the destination platform.
    var destinationBuildParameters: BuildParameters { get }

    /// Parameters used when building tools (macros and plugins).
    var toolsBuildParameters: BuildParameters { get }

    var buildProducts: AnySequence<ProductBuildDescription> { get }

    var buildModules: AnySequence<ModuleBuildDescription> { get }

    func createAPIToolCommonArgs(includeLibrarySearchPaths: Bool) throws -> [String]
    func createREPLArguments() throws -> [String]
}

public protocol BuildSystemFactory {
    func makeBuildSystem(
        explicitProduct: String?,
        enableAllTraits: Bool,
        cacheBuildManifest: Bool,
        productsBuildParameters: BuildParameters?,
        toolsBuildParameters: BuildParameters?,
        packageGraphLoader: (() async throws -> ModulesGraph)?,
        outputStream: OutputByteStream?,
        logLevel: Diagnostic.Severity?,
        observabilityScope: ObservabilityScope?,
        delegate: BuildSystemDelegate?
    ) async throws -> any BuildSystem
}

public struct BuildSystemProvider {
    // TODO: In the future, we may want this to be about specific capabilities of a build system rather than choosing a concrete one.
    public enum Kind: String, Codable, CaseIterable {
        case native
        case swiftbuild
        case xcode

        public var defaultValueDescription: String {
            switch self {
                case .native: "Native Build System"
                case .swiftbuild: "Swift Build build engine (Report issues at https://github.com/swiftlang/swift-package-manager/issues)"
                case .xcode: "aliased to the Swift Build build engine"
            }
        }
    }

    public let providers: [Kind: any BuildSystemFactory]

    public init(providers: [Kind: any BuildSystemFactory]) {
        self.providers = providers
    }

    public func createBuildSystem(
        kind: Kind,
        explicitProduct: String? = .none,
        enableAllTraits: Bool = false,
        cacheBuildManifest: Bool = true,
        productsBuildParameters: BuildParameters? = .none,
        toolsBuildParameters: BuildParameters? = .none,
        packageGraphLoader: (() async throws -> ModulesGraph)? = .none,
        outputStream: OutputByteStream? = .none,
        logLevel: Diagnostic.Severity? = .none,
        observabilityScope: ObservabilityScope? = .none,
        delegate: BuildSystemDelegate? = nil
    ) async throws -> any BuildSystem {
        guard let buildSystemFactory = self.providers[kind] else {
            throw Errors.buildSystemProviderNotRegistered(kind: kind)
        }
        return try await buildSystemFactory.makeBuildSystem(
            explicitProduct: explicitProduct,
            enableAllTraits: enableAllTraits,
            cacheBuildManifest: cacheBuildManifest,
            productsBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            packageGraphLoader: packageGraphLoader,
            outputStream: outputStream,
            logLevel: logLevel,
            observabilityScope: observabilityScope,
            delegate: delegate
        )
    }
}

private enum Errors: Swift.Error {
    case buildSystemProviderNotRegistered(kind: BuildSystemProvider.Kind)
}

public enum BuildSystemUtilities {
    /// Returns the build path from the environment, if present.
    public static func getEnvBuildPath(workingDir: AbsolutePath) throws -> AbsolutePath? {
        // Don't rely on build path from env for SwiftPM's own tests.
        guard Environment.current["SWIFTPM_TESTS_MODULECACHE"] == nil else { return nil }
        guard let env = Environment.current["SWIFTPM_BUILD_DIR"] else { return nil }
        return try AbsolutePath(validating: env, relativeTo: workingDir)
    }
}
