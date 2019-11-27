/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
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
    public let allProducts: Set<ResolvedProduct>

    /// The set of package dependencies required for a fully resolved graph.
    ///
    //// This set will also have references to packages that are currently present
    /// in the graph due to loading errors. This set doesn't include the root packages.
    public let requiredDependencies: Set<PackageReference>

    /// Returns true if a given target is present in root packages.
    public func isInRootPackages(_ target: ResolvedTarget) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap({ $0.targets }).contains(target)
    }

    public func isRootPackage(_ package: ResolvedPackage) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.contains(package)
    }

    /// All root and root dependency packages provided as input to the graph.
    public let inputPackages: [ResolvedPackage]

    /// Construct a package graph directly.
    public init(
        rootPackages: [ResolvedPackage],
        rootDependencies: [ResolvedPackage] = [],
        requiredDependencies: Set<PackageReference>
    ) {
        self.rootPackages = rootPackages
        self.requiredDependencies = requiredDependencies
        self.inputPackages = rootPackages + rootDependencies
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

        // Compute the reachable targets and products.
        let inputTargets = inputPackages.flatMap { $0.targets }
        let inputProducts = inputPackages.flatMap { $0.products }
        let recursiveDependencies = inputTargets.lazy.flatMap { $0.recursiveDependencies() }

        self.reachableTargets = Set(inputTargets).union(recursiveDependencies.compactMap { $0.target })
        self.reachableProducts = Set(inputProducts).union(recursiveDependencies.compactMap { $0.product })
    }

    /// Computes a map from each executable target in any of the root packages to the corresponding test targets.
    public func computeTestTargetsForExecutableTargets() -> [ResolvedTarget: [ResolvedTarget]] {
        var result = [ResolvedTarget: [ResolvedTarget]]()

        let rootTargets = rootPackages.map({ $0.targets }).flatMap({ $0 })

        // Create map of test target to set of its direct dependencies.
        let testTargetDepMap: [ResolvedTarget: Set<ResolvedTarget>] = {
            let testTargetDeps = rootTargets.filter({ $0.type == .test }).map({
                ($0, Set($0.dependencies.compactMap({ $0.target })))
            })
            return Dictionary(uniqueKeysWithValues: testTargetDeps)
        }()

        for target in rootTargets where target.type == .executable {
            // Find all dependencies of this target within its package.
            let dependencies = try! topologicalSort(target.dependencies, successors: {
                $0.dependencies.compactMap { $0.target }.map { .target($0, conditions: []) }
            }).compactMap({ $0.target })

            // Include the test targets whose dependencies intersect with the
            // current target's (recursive) dependencies.
            let testTargets = testTargetDepMap.filter({ (testTarget, deps) in
                !deps.intersection(dependencies + [target]).isEmpty
            }).map({ $0.key })

            result[target] = testTargets
        }

        return result
    }
}
