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

import PackageLoading
import PackageModel
import TSCBasic

/// A node used while loading the packages in a resolved graph.
///
/// This node uses the product filter that was already finalized during resolution.
///
/// - SeeAlso: DependencyResolutionNode
public struct GraphLoadingNode: Equatable, Hashable {

    /// The package identity.
    public let identity: PackageIdentity

    /// The package manifest.
    public let manifest: Manifest

    /// The product filter applied to the package.
    public let productFilter: ProductFilter

    /// The file system to use for loading the given package.
    public let fileSystem: FileSystem

    public init(identity: PackageIdentity, manifest: Manifest, productFilter: ProductFilter, fileSystem: FileSystem) {
        self.identity = identity
        self.manifest = manifest
        self.productFilter = productFilter
        self.fileSystem = fileSystem
    }

    /// Returns the dependencies required by this node.
    internal func requiredDependencies() -> [PackageDependency] {
        return manifest.dependenciesRequired(for: productFilter)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(manifest)
        hasher.combine(productFilter)
    }

    public static func == (lhs: GraphLoadingNode, rhs: GraphLoadingNode) -> Bool {
        return lhs.identity == rhs.identity && lhs.manifest == rhs.manifest && lhs.productFilter == rhs.productFilter
    }
}

extension GraphLoadingNode: CustomStringConvertible {
    public var description: String {
        switch productFilter {
        case .everything:
            return self.identity.description
        case .specific(let set):
            return "\(self.identity.description)[\(set.sorted().joined(separator: ", "))]"
        }
    }
}
