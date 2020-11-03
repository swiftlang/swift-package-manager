/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageLoading
import PackageModel
import SourceControl
import struct TSCUtility.Version

/// A container of packages.
///
/// This is the top-level unit of package resolution, i.e. the unit at which
/// versions are associated.
///
/// It represents a package container (e.g., a source repository) which can be
/// identified unambiguously and which contains a set of available package
/// versions and the ability to retrieve the dependency constraints for each of
/// those versions.
///
/// We use the "container" terminology here to differentiate between two
/// conceptual notions of what the package is: (1) informally, the repository
/// containing the package, but from which a package cannot be loaded by itself
/// and (2) the repository at a particular version, at which point the package
/// can be loaded and dependencies enumerated.
///
/// This is also designed in such a way to extend naturally to multiple packages
/// being contained within a single repository, should we choose to support that
/// later.
public protocol PackageContainer {

    /// The identifier for the package.
    var identifier: PackageReference { get }

    /// Returns true if the tools version is compatible at the given version.
    func isToolsVersionCompatible(at version: Version) -> Bool

    /// Get the list of versions which are available for the package.
    ///
    /// The list will be returned in sorted order, with the latest version *first*.
    /// All versions will not be requested at once. Resolver will request the next one only
    /// if the previous one did not satisfy all constraints.
    func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version>

    /// Get the list of versions in the repository sorted in the reverse order, that is the latest
    /// version appears first.
    var reversedVersions: [Version] { get }

    // FIXME: We should perhaps define some particularly useful error codes
    // here, so the resolver can handle errors more meaningfully.
    //
    /// Fetch the declared dependencies for a particular version.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Precondition: `versions.contains(version)`
    /// - Throws: If the version could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint]

    /// Fetch the declared dependencies for a particular revision.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Throws: If the revision could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint]

    /// Fetch the dependencies of an unversioned package container.
    ///
    /// NOTE: This method should not be called on a versioned container.
    func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint]

    /// Get the updated identifier at a bound version.
    ///
    /// This can be used by the containers to fill in the missing information that is obtained
    /// after the container is available. The updated identifier is returned in result of the
    /// dependency resolution.
    func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference
}

// MARK: -

/// An individual constraint onto a container.
public struct PackageContainerConstraint: Equatable, Hashable {

    /// The identifier for the container the constraint is on.
    public let identifier: PackageReference

    /// The constraint requirement.
    public let requirement: PackageRequirement

    /// The required products.
    public let products: ProductFilter

    /// Create a constraint requiring the given `container` satisfying the
    /// `requirement`.
    public init(container identifier: PackageReference, requirement: PackageRequirement, products: ProductFilter) {
        self.identifier = identifier
        self.requirement = requirement
        self.products = products
    }

    /// Create a constraint requiring the given `container` satisfying the
    /// `versionRequirement`.
    public init(container identifier: PackageReference, versionRequirement: VersionSetSpecifier, products: ProductFilter) {
        self.init(container: identifier, requirement: .versionSet(versionRequirement), products: products)
    }
}

extension PackageContainerConstraint: CustomStringConvertible {
    public var description: String {
        return "Constraint(\(identifier), \(requirement), \(products)"
    }
}

// MARK: -

/// An interface for resolving package containers.
public protocol PackageContainerProvider {
    /// Get the container for a particular identifier asynchronously.
    func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    )
}

// MARK: -

/// Base class for the package container.
public class BasePackageContainer: PackageContainer {
    public typealias Identifier = PackageReference

    public let identifier: Identifier

    let mirrors: DependencyMirrors

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The current tools version in use.
    let currentToolsVersion: ToolsVersion

    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        fatalError("This should never be called")
    }

    public var reversedVersions: [Version] {
        fatalError("This should never be called")
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> Identifier {
        fatalError("This should never be called")
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        fatalError("This should never be called")
    }

    init(
        _ identifier: Identifier,
        mirrors: DependencyMirrors,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.identifier = identifier
        self.mirrors = mirrors
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
    }

    public var isRemoteContainer: Bool? {
        return nil
    }
}
