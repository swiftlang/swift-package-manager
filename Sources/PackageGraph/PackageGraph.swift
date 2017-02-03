/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageModel

/// A collection of packages.
public struct PackageGraph {
    /// The root packages.
    public let rootPackages: [ResolvedPackage]

    /// The complete list of contained packages, in topological order starting
    /// with the root packages.
    public let packages: [ResolvedPackage]

    /// Returns list of all modules (reachable from root packages) in the graph.
    // FIXME: This can create inconsistency between what we compile and what we link.
    // Clients should always get the products and then operate on that instead of asking for modules.
    public let modules: [ResolvedModule]

    /// Returns true if a given module is present in root packages.
    public func isInRootPackages(_ module: ResolvedModule) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap{$0.modules}.contains(module)
    }
    
    /// Construct a package graph directly.
    public init(rootPackages: [ResolvedPackage]) {
        self.rootPackages = rootPackages
        self.packages = try! topologicalSort(rootPackages, successors: { $0.dependencies })
        self.modules = try! topologicalSort(rootPackages.flatMap{$0.modules}, successors: { $0.dependencies })
    }

    /// A sequence of all of the products in the graph.
    ///
    /// This yields all products in topological order starting with the root package.
    public func products(includingExternalTestProducts: Bool = false) -> AnySequence<ResolvedProduct> {
        return AnySequence(packages.lazy.flatMap{ package -> [ResolvedProduct] in
            if self.rootPackages.contains(package) {
                return package.products
            } else {
                return package.products.filter{ $0.type != .test }
            }
        })
    }
}
