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

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.OutputByteStream
import enum TSCBasic.ProcessEnv

/// An enum representing what subset of the package to build.
public enum BuildSubset {
    /// Represents the subset of all products and non-test targets.
    case allExcludingTests

    /// Represents the subset of all products and targets.
    case allIncludingTests

    /// Represents a specific product.
    case product(String)

    /// Represents a specific target.
    case target(String)
}

/// A protocol that represents a build system used by SwiftPM for all build operations. This allows factoring out the
/// implementation details between SwiftPM's `BuildOperation` and the XCBuild backed `XCBuildSystem`.
public protocol BuildSystem: Cancellable {

    /// The delegate used by the build system.
    var delegate: BuildSystemDelegate? { get }

    /// The test products that this build system will build.
    var builtTestProducts: [BuiltTestProduct] { get }

    /// Returns the package graph used by the build system.
    func getPackageGraph() throws -> PackageGraph

    /// Builds a subset of the package graph.
    /// - Parameters:
    ///   - subset: The subset of the package graph to build.
    func build(subset: BuildSubset) throws

    var buildPlan: BuildPlan { get throws }
}

extension BuildSystem {
    /// Builds the default subset: all targets excluding tests.
    public func build() throws {
        try build(subset: .allExcludingTests)
    }
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
            return try buildParameters.binaryPath(for: product)
        }
    }
}

public protocol BuildPlan {
    var buildParameters: BuildParameters { get }
    var buildProducts: AnySequence<ProductBuildDescription> { get }

    func createAPIToolCommonArgs(includeLibrarySearchPaths: Bool) throws -> [String]
    func createREPLArguments() throws -> [String]
}

public struct BuildSystemProvider {
    // TODO: In the future, we may want this to be about specific capabilities of a build system rather than choosing a concrete one.
    public enum Kind: String, CaseIterable {
        case native
        case xcode
    }

    public typealias Provider = (
        _ explicitProduct: String?,
        _ cacheBuildManifest: Bool,
        _ customBuildParameters: BuildParameters?,
        _ customPackageGraphLoader: (() throws -> PackageGraph)?,
        _ customOutputStream: OutputByteStream?,
        _ customLogLevel: Diagnostic.Severity?,
        _ customObservabilityScope: ObservabilityScope?
    ) throws -> BuildSystem

    public let providers: [Kind:Provider]

    public init(providers: [Kind:Provider]) {
        self.providers = providers
    }

    public func createBuildSystem(
        kind: Kind,
        explicitProduct: String? = .none,
        cacheBuildManifest: Bool = true,
        customBuildParameters: BuildParameters? = .none,
        customPackageGraphLoader: (() throws -> PackageGraph)? = .none,
        customOutputStream: OutputByteStream? = .none,
        customLogLevel: Diagnostic.Severity? = .none,
        customObservabilityScope: ObservabilityScope? = .none
    ) throws -> BuildSystem {
        guard let provider = self.providers[kind] else {
            throw Errors.buildSystemProviderNotRegistered(kind: kind)
        }
        return try provider(explicitProduct, cacheBuildManifest, customBuildParameters, customPackageGraphLoader, customOutputStream, customLogLevel, customObservabilityScope)
    }
}

private enum Errors: Swift.Error {
    case buildSystemProviderNotRegistered(kind: BuildSystemProvider.Kind)
}

public enum BuildSystemUtilities {
    /// Returns the build path from the environment, if present.
    public static func getEnvBuildPath(workingDir: AbsolutePath) throws -> AbsolutePath? {
        // Don't rely on build path from env for SwiftPM's own tests.
        guard ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"] == nil else { return nil }
        guard let env = ProcessEnv.vars["SWIFTPM_BUILD_DIR"] else { return nil }
        return try AbsolutePath(validating: env, relativeTo: workingDir)
    }
}
