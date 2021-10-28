/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageLoading
import PackageModel
import TSCBasic

/// A node used while loading the packages in a resolved graph.
///
/// This node uses the product filter that was already finalized during resolution.
///
/// - SeeAlso: DependencyResolutionNode
// FIXME: tomer deprecate or replace withe some other manifest envelope
public struct GraphLoadingNode: Equatable, Hashable {

    /// The package identity.
    public let identity: PackageIdentity

    /// The package manifest.
    public let manifest: Manifest

    public init(identity: PackageIdentity, manifest: Manifest) {
        self.identity = identity
        self.manifest = manifest
        //self.productFilter = productFilter
    }

    /// Returns the dependencies required by this node.
    internal func requiredDependencies() -> [PackageDependency] {
        return self.manifest.requiredDependencies()
    }
}

extension GraphLoadingNode: CustomStringConvertible {
    public var description: String {
        return self.identity.description
    }
}
