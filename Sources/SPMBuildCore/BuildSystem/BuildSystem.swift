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
import struct PackageModel.PackageIdentity

import protocol TSCBasic.OutputByteStream

/// An enum representing what subset of the package to build.
public enum BuildSubset: Equatable {
    /// Represents the subset of all products and non-test targets.
    ///
    /// When `package` is non-nil, the subset is scoped to that
    /// workspace member. Nil means "workspace-wide / whole graph"
    /// (the pre-workspaces behavior).
    case allExcludingTests(package: PackageIdentity? = nil)

    /// Represents the subset of all products and targets.
    ///
    /// When `package` is non-nil, the subset is scoped to that
    /// workspace member. Nil means "workspace-wide / whole graph".
    case allIncludingTests(package: PackageIdentity? = nil)

    /// Represents a specific product. Allows to set a specific
    /// destination if it's known.
    ///
    /// When `package` is non-nil, the product name is scoped to the
    /// named workspace member (disambiguating products of the same
    /// name across multiple members). When `package` is nil, the
    /// product is looked up against the full graph as before.
    case product(
        String,
        for: BuildParameters.Destination? = .none,
        package: PackageIdentity? = nil,
    )

    /// Represents a specific target. Allows to set a specific
    /// destination if it's known.
    ///
    /// When `package` is non-nil, the target name is scoped to the
    /// named workspace member.
    case target(
        String,
        for: BuildParameters.Destination? = .none,
        package: PackageIdentity? = nil,
    )

    /// Represents all non-test products/targets belonging to a specific
    /// workspace member's package. Populated when a `Workspace.swift`
    /// is discovered and the invoking command is focused on a single
    /// member (e.g. CWD is inside that member, or `--package <identity>`
    /// was supplied). Only honored by the Swift Build build system;
    /// the native build system rejects it as a hard error.
    case workspaceMember(PackageIdentity)
}

extension BuildSubset {
    /// Validates a workspace-scoped subset against the loaded package
    /// graph. Callers dispatch on the result — a `nil` return means the
    /// subset is valid and can be routed to the build system; a non-nil
    /// return is the diagnostic to emit before failing the invocation.
    ///
    /// Currently checks two conditions:
    /// - `.product(name, package: X)` — `name` must be one of member
    ///   `X`'s declared products.
    /// - `.target(name, package: X)` — `name` must be one of member
    ///   `X`'s declared targets (modules).
    ///
    /// All other subset shapes (whole-graph, unscoped `.product` /
    /// `.target`, `.workspaceMember`) have no cross-member scoping to
    /// validate and return `nil`. When `package` is set but the member
    /// isn't in `graph.rootPackages`, this also returns `nil` — the
    /// missing-member case is caught earlier by the CLI-level
    /// `unknownWorkspaceMember` diagnostic.
    @_spi(SwiftPMInternal)
    public func validate(against graph: ModulesGraph) -> Basics.Diagnostic? {
        switch self {
        case .product(let name, _, let package?):
            guard let member = graph.rootPackages.first(where: { $0.identity == package }) else {
                return nil
            }
            let known = Set(member.products.map { PackageIdentity.plain($0.name) })
            guard !known.contains(.plain(name)) else { return nil }
            return .unknownProductInMember(requested: name, package: package, known: known)
        case .target(let name, _, let package?):
            guard let member = graph.rootPackages.first(where: { $0.identity == package }) else {
                return nil
            }
            let known = Set(member.modules.map { PackageIdentity.plain($0.name) })
            guard !known.contains(.plain(name)) else { return nil }
            return .unknownTargetInMember(requested: name, package: package, known: known)
        case .product, .target,
             .allExcludingTests, .allIncludingTests,
             .workspaceMember:
            return nil
        }
    }
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
    case dependencyGraph
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

    /// The path to the build directory for the given build parameters.
    func buildProductsPath(for parameters: BuildParameters) async throws -> AbsolutePath
}

extension BuildSystem {
    /// Builds the default subset: all targets excluding tests with no extra build outputs.
    @discardableResult
    public func build() async throws -> BuildResult {
        try await build(subset: .allExcludingTests(), buildOutputs: [])
    }

    /// The path to the index store directory for the given build parameters.
    public func indexStore(for parameters: BuildParameters) async throws -> AbsolutePath {
        assert(parameters.indexStoreMode != .off, "index store is disabled")
        return try await buildProductsPath(for: parameters).appending(components: "index", "store")
    }

    /// The path to the code coverage directory for the given build parameters.
    public func codeCovPath(for parameters: BuildParameters) async throws -> AbsolutePath {
        try await buildProductsPath(for: parameters).appending("codecov")
    }

    /// The path to the code coverage profdata file for the given build parameters.
    public func codeCovDataFile(for parameters: BuildParameters) async throws -> AbsolutePath {
        try await codeCovPath(for: parameters).appending("default.profdata")
    }

    /// The path to the test output file for the given build parameters.
    public func testOutputPath(for parameters: BuildParameters) async throws -> AbsolutePath {
        try await buildProductsPath(for: parameters).appending(component: "testOutput.txt")
    }

    /// Returns the path to the binary of a product for the given build parameters.
    public func binaryPath(for product: ResolvedProduct, parameters: BuildParameters) async throws -> AbsolutePath {
        try await buildProductsPath(for: parameters).appending(parameters.binaryRelativePath(for: product))
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
    public struct BuiltArtifact {
        public let name: String

        public let artifact: PluginInvocationBuildResult.BuiltArtifact

        public let umbrellaTestProductName: String?

        public init(
            name: String,
            artifact: PluginInvocationBuildResult.BuiltArtifact,
            umbrellaTestProductName: String?
        ) {
            self.name = name
            self.artifact = artifact
            self.umbrellaTestProductName = umbrellaTestProductName
        }
    }

    package init(
        serializedDiagnosticPathsByTargetName: Result<[String: [AbsolutePath]], Error>,
        symbolGraph: SymbolGraphResult? = nil,
        buildPlan: BuildPlan? = nil,
        replArguments: CLIArguments?,
        builtArtifacts: [BuiltArtifact]? = nil,
        // TODO: echeng3805, there's probably a better type for this?
        dependencyGraph: [String: [String]]? = nil
    ) {
        self.serializedDiagnosticPathsByTargetName = serializedDiagnosticPathsByTargetName
        self.symbolGraph = symbolGraph
        self.buildPlan = buildPlan
        self.replArguments = replArguments
        self.builtArtifacts = builtArtifacts
        self.dependencyGraph = dependencyGraph
    }

    public let replArguments: CLIArguments?
    public let symbolGraph: SymbolGraphResult?
    public let buildPlan: BuildPlan?
    public let dependencyGraph: [String: [String]]?

    public var serializedDiagnosticPathsByTargetName: Result<[String: [AbsolutePath]], Error>
    public var builtArtifacts: [BuiltArtifact]?
}

public protocol ProductBuildDescription {
    /// The reference to the product.
    var package: ResolvedPackage { get }

    /// The reference to the product.
    var product: ResolvedProduct { get }

    /// The build parameters.
    var buildParameters: BuildParameters { get }

    /// The build products directory — the path under which built binaries, libraries, and other
    /// products are placed for the corresponding build system/parameters.
    var productsPath: AbsolutePath { get }
}

extension ProductBuildDescription {
    /// The path to the product binary produced.
    public var binaryPath: AbsolutePath {
        get throws {
            try self.productsPath.appending(self.buildParameters.binaryRelativePath(for: product))
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
                case .native: "Native Build System (deprecated)"
                case .swiftbuild: "Swift Build build engine (default)"
                case .xcode: "Xcode build system integration (deprecated)"
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
