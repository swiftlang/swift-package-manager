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

/// Delegate interface for dependency resoler status.
public protocol DependencyResolverDelegate {
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
