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

    /// The list of all targets reachable from root targets.
    public let reachableTargets: Set<ResolvedTarget>

    /// The list of all products reachable from root targets.
    public let reachableProducts: Set<ResolvedProduct>

    /// Returns all the targets in the graph, regardless if they are reachable from the root targets or not.
    public let allTargets: Set<ResolvedTarget>
 
    /// Returns all the products in the graph, regardless if they are reachable from the root targets or not.
    public var allProducts: Set<ResolvedProduct>

    /// Returns true if a given target is present in root packages.
    public func isInRootPackages(_ target: ResolvedTarget) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap({ $0.targets }).contains(target)
    }

    public func isRootPackage(_ package: ResolvedPackage) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.contains(package)
    }

    /// Construct a package graph directly.
    public init(rootPackages: [ResolvedPackage], rootDependencies: [ResolvedPackage] = []) {
        self.rootPackages = rootPackages
        let inputPackages = rootPackages + rootDependencies
        self.packages = try! topologicalSort(inputPackages, successors: { $0.dependencies })

        allTargets = Set(packages.flatMap({ package -> [ResolvedTarget] in
            if rootPackages.contains(package) {
                return package.targets
            } else {
                // Don't include tests targets from non-root packages so swift-test doesn't
                // try to run them.
                return package.targets.filter({ $0.type != .test })
            }
        }))

        allProducts = Set(packages.flatMap({ package -> [ResolvedProduct] in
            if rootPackages.contains(package) {
                return package.products
            } else {
                // Don't include tests products from non-root packages so swift-test doesn't
                // try to run them.
                return package.products.filter({ $0.type != .test })
            }
        }))

        // Compute the input targets.
        let inputTargets = inputPackages.flatMap({ $0.targets }).map(ResolvedTarget.Dependency.target)
        // Find all the dependencies of the root targets.
        let dependencies = try! topologicalSort(inputTargets, successors: { $0.dependencies })

        // Separate out the products and targets but maintain their topological order.
        var reachableTargets: Set<ResolvedTarget> = []
        var reachableProducts = Set(inputPackages.flatMap({ $0.products }))

        for dependency in dependencies {
            switch dependency {
            case .target(let target):
                reachableTargets.insert(target)
            case .product(let product):
                reachableProducts.insert(product)
            }
        }

        self.reachableTargets = reachableTargets
        self.reachableProducts = reachableProducts
    }
}
