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
import PackageLoading
import PackageModel

/// A node used while loading the packages in a resolved graph.
///
/// This node uses the product filter that was already finalized during resolution.
///
/// - SeeAlso: ``DependencyResolutionNode``
public struct GraphLoadingNode: Equatable, Hashable {
    /// The package identity.
    public let identity: PackageIdentity

    /// The package manifest.
    public let manifest: Manifest

    /// The product filter applied to the package.
    public let productFilter: ProductFilter

    /// The enabled traits for this package.
    package var enabledTraits: Set<String>

    public init(
        identity: PackageIdentity,
        manifest: Manifest,
        productFilter: ProductFilter,
        enabledTraits: Set<String>?
    ) throws {
        self.identity = identity
        self.manifest = manifest
        self.productFilter = productFilter

        // This the point where we flatten the enabled traits and resolve the recursive traits
        var recursiveEnabledTraits = enabledTraits ?? []
        let areDefaultsEnabled = recursiveEnabledTraits.remove("defaults") != nil

        // We are going to calculate which traits are actually enabled for a node here. To do this
        // we have to check if default traits should be used and then flatten all the enabled traits.
        for trait in recursiveEnabledTraits {
            // Check if the enabled trait is a valid trait
            if self.manifest.traits.first(where: { $0.name == trait }) == nil {
                // The enabled trait is invalid
                throw ModuleError.invalidTrait(package: identity, trait: trait)
            }
        }

        // We have to enable all default traits if no traits are enabled or the defaults are explicitly enabled
        if enabledTraits == nil || areDefaultsEnabled {
            recursiveEnabledTraits.formUnion(self.manifest.traits.lazy.filter { $0.isDefault }.map { $0.name })
        }

        while true {
            let flattendEnabledTraits = Set(self.manifest.traits
                .lazy
                .filter { recursiveEnabledTraits.contains($0.name) }
                .map { $0.enabledTraits }
                .joined()
            )
            let newRecursiveEnabledTraits = recursiveEnabledTraits.union(flattendEnabledTraits)
            if newRecursiveEnabledTraits.count == recursiveEnabledTraits.count {
                break
            } else {
                recursiveEnabledTraits = newRecursiveEnabledTraits
            }
        }

        self.enabledTraits = recursiveEnabledTraits
    }

    /// Returns the dependencies required by this node.
    internal var requiredDependencies: [PackageDependency] {
        return self.manifest.dependenciesRequired(for: self.productFilter)
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
