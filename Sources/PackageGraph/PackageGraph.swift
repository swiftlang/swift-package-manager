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
    public let targets: Set<ResolvedTarget>

    /// Contains all the products of the root packages and the product dependencies of the root targets.
    /// i.e. this array will not contain the products which are not needed to be built.
    public let products: Set<ResolvedProduct>

    /// Returns all the targets in the graph, regardless if they are reachable from the root targets or not.
    public let allTargets: Set<ResolvedTarget>

    /// Returns all the products in the graph, regardless if they are reachable from the root targets or not.
    public var allProducts: Set<ResolvedProduct>

    /// Returns true if a given target is present in root packages.
    public func isInRootPackages(_ target: ResolvedTarget) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap({ $0.targets }).contains(target)
    }

    /// Construct a package graph directly.
    public init(rootPackages: [ResolvedPackage], rootDependencies: [ResolvedPackage] = []) {
        self.rootPackages = rootPackages
        let inputPackages = rootPackages + rootDependencies
        self.packages = try! topologicalSort(inputPackages, successors: { $0.dependencies })
        allTargets = Set(packages.flatMap({ $0.targets }))
        allProducts = Set(packages.flatMap({ $0.products }))

        // Compute the input targets.
        let inputTargets = inputPackages.flatMap({ $0.targets }).map(ResolvedTarget.Dependency.target)
        // Find all the dependencies of the root targets.
        let dependencies = try! topologicalSort(inputTargets, successors: { $0.dependencies })

        // Separate out the products and targets but maintain their topological order.
        var targets: Set<ResolvedTarget> = []
        var products = Set(inputPackages.flatMap({ $0.products }))

        for dependency in dependencies {
            switch dependency {
            case .target(let target):
                targets.insert(target)
            case .product(let product):
                products.insert(product)
            }
        }

        self.targets = targets
        self.products = products
    }
}
