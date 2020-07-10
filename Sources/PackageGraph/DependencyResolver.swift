/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel
import struct TSCUtility.Version
import class Foundation.NSDate

public enum DependencyResolverError: Error, Equatable, CustomStringConvertible {
     /// A revision-based dependency contains a local package dependency.
    case revisionDependencyContainsLocalPackage(dependency: String, localPackage: String)

    public static func == (lhs: DependencyResolverError, rhs: DependencyResolverError) -> Bool {
        switch (lhs, rhs) {
        case (.revisionDependencyContainsLocalPackage(let a1, let b1), .revisionDependencyContainsLocalPackage(let a2, let b2)):
            return a1 == a2 && b1 == b2
        }
    }

    public var description: String {
        switch self {
        case .revisionDependencyContainsLocalPackage(let dependency, let localPackage):
            return "package '\(dependency)' is required using a revision-based requirement and it depends on local package '\(localPackage)', which is not supported"
        }
    }
}

/// A requirement that a package must satisfy.
public enum PackageRequirement: Hashable {

    /// The requirement is specified by the version set.
    case versionSet(VersionSetSpecifier)

    /// The requirement is specified by the revision.
    ///
    /// The revision string (identifier) should be valid and present in the
    /// container. Only one revision requirement per container is possible
    /// i.e. two revision requirements for same container will lead to
    /// unsatisfiable resolution. The revision requirement can either come
    /// from initial set of constraints or from dependencies of a revision
    /// requirement.
    case revision(String)

    /// Un-versioned requirement i.e. a version should not resolved.
    case unversioned
}

extension PackageRequirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .versionSet(let versionSet): return versionSet.description
        case .revision(let revision): return revision
        case .unversioned: return "unversioned"
        }
    }
}

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

/// An interface for resolving package containers.
public protocol PackageContainerProvider {
    /// Get the container for a particular identifier asynchronously.
    func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    )
}

/// An individual constraint onto a container.
public struct PackageContainerConstraint: CustomStringConvertible, Equatable, Hashable {

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

    public var description: String {
        return "Constraint(\(identifier), \(requirement), \(products)"
    }
}

/// Delegate interface for dependency resoler status.
public protocol DependencyResolverDelegate {
}

/// A bound version for a package within an assignment.
public enum BoundVersion: Equatable, CustomStringConvertible {
    /// The assignment should not include the package.
    ///
    /// This is different from the absence of an assignment for a particular
    /// package, which only indicates the assignment is agnostic to its
    /// version. This value signifies the package *may not* be present.
    case excluded

    /// The version of the package to include.
    case version(Version)

    /// The package assignment is unversioned.
    case unversioned

    /// The package assignment is this revision.
    case revision(String)

    public var description: String {
        switch self {
        case .excluded:
            return "excluded"
        case .version(let version):
            return version.description
        case .unversioned:
            return "unversioned"
        case .revision(let identifier):
            return identifier
        }
    }
}

public class DependencyResolver {
    public typealias Binding = (container: PackageReference, binding: BoundVersion, products: ProductFilter)

    /// The dependency resolver result.
    public enum Result {
        /// A valid and complete assignment was found.
        case success([Binding])

        /// The resolver encountered an error during resolution.
        case error(Swift.Error)
    }
}

/// A node in the dependency resolution graph.
///
/// See the documentation of each case for more detailed descriptions of each kind and how they interact.
///
/// - SeeAlso: `GraphLoadingNode`
public enum DependencyResolutionNode: Equatable, Hashable, CustomStringConvertible {

    /// An empty package node.
    ///
    /// This node indicates that a package needs to be present, but does not indicate that any of its contents are needed.
    ///
    /// Empty package nodes are always leaf nodes; they have no dependencies.
    case empty(package: PackageReference)

    /// A product node.
    ///
    /// This node indicates that a particular product in a particular package is required.
    ///
    /// Product nodes always have dependencies. A product node has...
    ///
    /// - one implicit dependency on its own package at an exact version (as an empty package node).
    ///   This dependency is what ensures the resolver does not select two products from the same package at different versions.
    /// - zero or more dependencies on the product nodes of other packages.
    ///   These are all the external products required to build all of the targets vended by this product.
    ///   They derive from the manifest.
    ///
    ///   Tools versions before 5.2 do not know which products belong to which packages, so each product is required from every dependency.
    ///   Since a non‐existant product ends up with only its implicit dependency on its own package,
    ///   only whichever package contains the product will end up adding additional constraints.
    ///   See `ProductFilter` and `Manifest.register(...)`.
    case product(String, package: PackageReference)

    /// A root node.
    ///
    /// This node indicates a root node in the graph, which is required no matter what.
    ///
    /// Root nodes may have dependencies. A root node has...
    ///
    /// - zero or more dependencies on each external product node required to build any of its targets (vended or not).
    /// - zero or more dependencies directly on external empty package nodes.
    ///   This special case occurs when a dependecy is declared but not used.
    ///   It is a warning condition, and builds do not actually need these dependencies.
    ///   However, forcing the graph to resolve and fetch them anyway allows the diagnostics passes access
    ///   to the information needed in order to provide actionable suggestions to help the user stitch up the dependency declarations properly.
    case root(package: PackageReference)

    /// The package.
    public var package: PackageReference {
        switch self {
        case .empty(let package), .product(_, let package), .root(let package):
            return package
        }
    }

    /// The name of the specific product if the node is a product node, otherwise `nil`.
    public var specificProduct: String? {
        switch self {
        case .empty, .root:
            return nil
        case .product(let product, _):
            return product
        }
    }

    // To ensure cyclical dependencies are detected properly,
    // hashing cannot include whether the node behaves as a root.
    private struct Identity: Equatable, Hashable {
        fileprivate let package: PackageReference
        fileprivate let specificProduct: String?
    }
    private var identity: Identity {
        return Identity(package: package, specificProduct: specificProduct)
    }
    public static func ==(lhs: DependencyResolutionNode, rhs: DependencyResolutionNode) -> Bool {
        return lhs.identity == rhs.identity
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    /// Assembles the product filter to use on the manifest for this node to determine it’s dependencies.
    internal func productFilter() -> ProductFilter {
        switch self {
        case .empty:
            return .specific([])
        case .product(let product, _):
            return .specific([product])
        case .root:
            return .everything
        }
    }

    /// Returns the dependency that a product has on its own package, if relevant.
    ///
    /// This is the constraint that requires all products from a package resolve to the same version.
    internal func versionLock(version: Version) -> RepositoryPackageConstraint? {
        // Don’t create a version lock for anything but a product.
        guard specificProduct != nil else { return nil }
        return RepositoryPackageConstraint(
            container: package,
            versionRequirement: .exact(version),
            products: .specific([])
        )
    }

    /// Returns the dependency that a product has on its own package, if relevant.
    ///
    /// This is the constraint that requires all products from a package resolve to the same revision.
    internal func revisionLock(revision: String) -> RepositoryPackageConstraint? {
        // Don’t create a revision lock for anything but a product.
        guard specificProduct != nil else { return nil }
        return RepositoryPackageConstraint(
            container: package,
            requirement: .revision(revision),
            products: .specific([])
        )
    }

    public var description: String {
        return "\(package.name)\(productFilter())"
    }

    public func nameForDiagnostics() -> String {
        if let product = specificProduct {
            return "\(package.name)[\(product)]"
        } else {
            return "\(package.name)"
        }
    }
}
