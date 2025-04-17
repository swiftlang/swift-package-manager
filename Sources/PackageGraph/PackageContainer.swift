//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Dispatch
import PackageModel

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
    var package: PackageReference { get }

    var shouldInvalidatePinnedVersions: Bool { get }

    /// Returns true if the tools version is compatible at the given version.
    func isToolsVersionCompatible(at version: Version) async -> Bool

    /// Returns the tools version for the given version
    func toolsVersion(for version: Version) async throws -> ToolsVersion

    /// Get the list of versions which are available for the package.
    ///
    /// The list will be returned in sorted order, with the latest version *first*.
    /// All versions will not be requested at once. Resolver will request the next one only
    /// if the previous one did not satisfy all constraints.
    func toolsVersionsAppropriateVersionsDescending() async throws -> [Version]

    /// Get the list of versions in the repository sorted in the ascending order, that is the earliest
    /// version appears first.
    func versionsAscending() async throws -> [Version]

    /// Get the list of versions in the repository sorted in the descending order, that is the latest
    /// version appears first.
    func versionsDescending() async throws -> [Version]

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
    func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: Set<String>?) async throws -> [PackageContainerConstraint]

    /// Fetch the declared dependencies for a particular revision.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Throws: If the revision could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at revision: String, productFilter: ProductFilter, _ enabledTraits: Set<String>?) async throws -> [PackageContainerConstraint]

    /// Fetch the dependencies of an unversioned package container.
    ///
    /// NOTE: This method should not be called on a versioned container.
    func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: Set<String>?) async throws -> [PackageContainerConstraint]

    /// Get the updated identifier at a bound version.
    ///
    /// This can be used by the containers to fill in the missing information that is obtained
    /// after the container is available. The updated identifier is returned in result of the
    /// dependency resolution.
    func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference


    /// Fetch the enabled traits of a package container.
    ///
    /// NOTE: This method should only be called on root packages.
    func getEnabledTraits(traitConfiguration: TraitConfiguration?, version: Version?) async throws -> Set<String>
}

extension PackageContainer {
    public func reversedVersions() async throws -> [Version] {
        try await self.versionsDescending()
    }

    public func versionsDescending() async throws -> [Version] {
        try await self.versionsAscending().reversed()
    }

    public var shouldInvalidatePinnedVersions: Bool {
        return true
    }

    public func getEnabledTraits(traitConfiguration: TraitConfiguration?, version: Version? = nil) async throws -> Set<String> {
        return []
    }
}

public protocol CustomPackageContainer: PackageContainer {
    /// Retrieve the package using this package container.
    func retrieve(
       at version: Version,
       progressHandler: ((_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void)?,
       observabilityScope: ObservabilityScope
    ) throws -> AbsolutePath

    /// Get the custom file system for this package container.
    func getFileSystem() throws -> FileSystem?
}

public extension CustomPackageContainer {
    func retrieve(at version: Version, observabilityScope: ObservabilityScope) throws -> AbsolutePath {
        return try self.retrieve(at: version, progressHandler: .none, observabilityScope: observabilityScope)
    }
}

// MARK: - PackageContainerConstraint

/// An individual constraint onto a container.
public struct PackageContainerConstraint: Equatable, Hashable {

    /// The identifier for the container the constraint is on.
    public let package: PackageReference

    /// The constraint requirement.
    public let requirement: PackageRequirement

    /// The required products.
    public let products: ProductFilter

    /// The traits that have been enabled for the package.
    public let enabledTraits: Set<String>?

    /// Create a constraint requiring the given `container` satisfying the
    /// `requirement`.
    public init(package: PackageReference, requirement: PackageRequirement, products: ProductFilter, enabledTraits: Set<String>? = nil) {
        self.package = package
        self.requirement = requirement
        self.products = products
        self.enabledTraits = enabledTraits
    }

    /// Create a constraint requiring the given `container` satisfying the
    /// `versionRequirement`.
    public init(package: PackageReference, versionRequirement: VersionSetSpecifier, products: ProductFilter, enabledTraits: Set<String>? = nil) {
        self.init(package: package, requirement: .versionSet(versionRequirement), products: products, enabledTraits: enabledTraits)
    }

    /// Custom implementation for the hash method due to interference of traits in its computation.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(package)
        hasher.combine(requirement)
        hasher.combine(products)
    }

    /// Custom implementation to check equality due to interference of traits in its computation.
    static public func == (lhs: PackageContainerConstraint, rhs: PackageContainerConstraint) -> Bool {
        return lhs.package == rhs.package && lhs.requirement == rhs.requirement && lhs.products == rhs.products
    }
}

extension PackageContainerConstraint: CustomStringConvertible {
    public var description: String {
        return "Constraint(\(self.package), \(requirement), \(products), \(enabledTraits ?? [])"
    }
}

// MARK: - PackageContainerProvider

/// An interface for resolving package containers.
public protocol PackageContainerProvider {
    /// Get the container for a particular identifier asynchronously.

    @available(*, noasync, message: "Use the async alternative")
    func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<PackageContainer, Error>) -> Void
    )
}

public extension PackageContainerProvider {
    func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue
    ) async throws -> PackageContainer {
        try await withCheckedThrowingContinuation { continuation in
            self.getContainer(
                for: package,
                updateStrategy: updateStrategy,
                observabilityScope: observabilityScope,
                on: queue,
                completion: {
                    continuation.resume(with: $0)
                }
            )
        }
    }
}

/// Only used for source control containers and as such a mirror of RepositoryUpdateStrategy
/// This duplication is unfortunate - ideally this is not a concern of the ContainerProvider at all
/// but it is required give how PackageContainerProvider currently integrated into the resolver
public enum ContainerUpdateStrategy {
    case never
    case always
    case ifNeeded(revision: String)
}
