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

    /// Returns list of all targets (reachable from root targets) in the graph.
    public let modules: [ResolvedModule]

    /// Contains all the products of the root packages and the product dependencies of the root targets.
    /// i.e. this array will not contain the products which are not needed to be built.
    public let products: [ResolvedProduct]

    /// Returns true if a given module is present in root packages.
    public func isInRootPackages(_ module: ResolvedModule) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap{$0.modules}.contains(module)
    }

    /// The errors encountered while loading the package graph.
    public let errors: [Swift.Error]

    /// Construct a package graph directly.
    public init(rootPackages: [ResolvedPackage], errors: [Swift.Error] = []) {
        self.errors = errors
        self.rootPackages = rootPackages
        self.packages = try! topologicalSort(rootPackages, successors: { $0.dependencies })

        // Compute the root targets.
        let rootTargets = rootPackages.flatMap{$0.modules}.map(ResolvedModule.Dependency.target)
        // Find all the dependencies of the root targets.
        let dependencies = try! topologicalSort(rootTargets, successors: { $0.dependencies })

        // Separate out the products and targets but maintain their topological order.
        var targets: [ResolvedModule] = []
        var products = rootPackages.flatMap{$0.products}
        for dependency in dependencies {
            switch dependency {
            case .target(let target):
                targets.append(target)
            case .product(let product):
                products.append(product)
            }
        }

        self.modules = targets
        self.products = products
    }
}
