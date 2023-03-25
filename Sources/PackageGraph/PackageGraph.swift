//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageLoading
import PackageModel
import TSCBasic

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no targets.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case cycleDetected((path: [Manifest], cycle: [Manifest]))

    /// The product dependency not found.
    case productDependencyNotFound(package: String, targetName: String, dependencyProductName: String, dependencyPackageName: String?, dependencyProductInDecl: Bool)

    /// The package dependency already satisfied by a different dependency package
    case dependencyAlreadySatisfiedByIdentifier(package: String, dependencyLocation: String, otherDependencyURL: String, identity: PackageIdentity)

    /// The package dependency already satisfied by a different dependency package
    case dependencyAlreadySatisfiedByName(package: String, dependencyLocation: String, otherDependencyURL: String, name: String)

    /// The product dependency was found but the package name was not referenced correctly (tools version > 5.2).
    case productDependencyMissingPackage(
        productName: String,
        targetName: String,
        packageIdentifier: String
    )
    /// Dependency between a plugin and a dependent target/product of a given type is unsupported
    case unsupportedPluginDependency(targetName: String, dependencyName: String, dependencyType: String, dependencyPackage: String?)
    /// A product was found in multiple packages.
    case duplicateProduct(product: String, packages: [String])

    /// Duplicate aliases for a target found in a product.
    case multipleModuleAliases(target: String,
                               product: String,
                               package: String,
                               aliases: [String])
}

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

    /// Returns true if a given target is present in root packages and is not excluded for the given build environment.
    public func isInRootPackages(_ target: ResolvedTarget, satisfying buildEnvironment: BuildEnvironment) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap({ (package: ResolvedPackage) -> Set<ResolvedTarget> in
            let allDependencies = package.targets.flatMap { $0.dependencies }
            let unsatisfiedDependencies = allDependencies.filter { !$0.satisfies(buildEnvironment) }
            let unsatisfiedDependencyTargets = unsatisfiedDependencies.compactMap { (dep: ResolvedTarget.Dependency) -> ResolvedTarget? in
                switch dep {
                case .target(let target, _):
                    return target
                default:
                    return nil
                }
            }

            return Set(package.targets).subtracting(unsatisfiedDependencyTargets)
        }).contains(target)
    }

    public func isRootPackage(_ package: ResolvedPackage) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.contains(package)
    }

    private let targetsToPackages: [ResolvedTarget: ResolvedPackage]
    /// Returns the package that contains the target, or nil if the target isn't in the graph.
    public func package(for target: ResolvedTarget) -> ResolvedPackage? {
        return self.targetsToPackages[target]
    }


    private let productsToPackages: [ResolvedProduct: ResolvedPackage]
    /// Returns the package that contains the product, or nil if the product isn't in the graph.
    public func package(for product: ResolvedProduct) -> ResolvedPackage? {
        return self.productsToPackages[product]
    }

    /// All root and root dependency packages provided as input to the graph.
    public let inputPackages: [ResolvedPackage]

    /// Any binary artifacts referenced by the graph.
    public let binaryArtifacts: [PackageIdentity: [String: BinaryArtifact]]

    /// Construct a package graph directly.
    public init(
        rootPackages: [ResolvedPackage],
        rootDependencies: [ResolvedPackage] = [],
        dependencies requiredDependencies: Set<PackageReference>,
        binaryArtifacts: [PackageIdentity: [String: BinaryArtifact]]
    ) throws {
        self.rootPackages = rootPackages
        self.requiredDependencies = requiredDependencies
        self.inputPackages = rootPackages + rootDependencies
        self.binaryArtifacts = binaryArtifacts
        self.packages = try topologicalSort(inputPackages, successors: { $0.dependencies })

        // Create a mapping from targets to the packages that define them.  Here
        // we include all targets, including tests in non-root packages, since
        // this is intended for lookup and not traversal.
        self.targetsToPackages = packages.reduce(into: [:], { partial, package in
            package.targets.forEach{ partial[$0] = package }
        })

        allTargets = Set(packages.flatMap({ package -> [ResolvedTarget] in
            if rootPackages.contains(package) {
                return package.targets
            } else {
                // Don't include tests targets from non-root packages so swift-test doesn't
                // try to run them.
                return package.targets.filter({ $0.type != .test })
            }
        }))

        // Create a mapping from products to the packages that define them.  Here
        // we include all products, including tests in non-root packages, since
        // this is intended for lookup and not traversal.
        self.productsToPackages = packages.reduce(into: [:], { partial, package in
            package.products.forEach{ partial[$0] = package }
        })

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
        let recursiveDependencies = try inputTargets.lazy.flatMap { try $0.recursiveDependencies() }

        self.reachableTargets = Set(inputTargets).union(recursiveDependencies.compactMap { $0.target })
        self.reachableProducts = Set(inputProducts).union(recursiveDependencies.compactMap { $0.product })
    }

    /// Computes a map from each executable target in any of the root packages to the corresponding test targets.
    public func computeTestTargetsForExecutableTargets() throws -> [ResolvedTarget: [ResolvedTarget]] {
        var result = [ResolvedTarget: [ResolvedTarget]]()

        let rootTargets = rootPackages.map({ $0.targets }).flatMap({ $0 })

        // Create map of test target to set of its direct dependencies.
        let testTargetDepMap: [ResolvedTarget: Set<ResolvedTarget>] = try {
            let testTargetDeps = rootTargets.filter({ $0.type == .test }).map({
                ($0, Set($0.dependencies.compactMap{ $0.target }.filter{ $0.type != .plugin }))
            })
            return try Dictionary(throwingUniqueKeysWithValues: testTargetDeps)
        }()

        for target in rootTargets where target.type == .executable {
            // Find all dependencies of this target within its package. Note that we do not traverse plugin usages.
            let dependencies = try topologicalSort(target.dependencies, successors: {
                $0.dependencies.compactMap{ $0.target }.filter{ $0.type != .plugin }.map{ .target($0, conditions: []) }
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

extension PackageGraphError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noModules(let package):
            return "package '\(package)' contains no products"

        case .cycleDetected(let cycle):
            return "cyclic dependency declaration found: " +
            (cycle.path + cycle.cycle).map({ $0.displayName }).joined(separator: " -> ") +
            " -> " + cycle.cycle[0].displayName

        case .productDependencyNotFound(let package, let targetName, let dependencyProductName, let dependencyPackageName, let dependencyProductInDecl):
            if dependencyProductInDecl {
                return "product '\(dependencyProductName)' is declared in the same package '\(package)' and can't be used as a dependency for target '\(targetName)'."
            } else {
                return "product '\(dependencyProductName)' required by package '\(package)' target '\(targetName)' \(dependencyPackageName.map{ "not found in package '\($0)'" } ?? "not found")."
            }
        case .dependencyAlreadySatisfiedByIdentifier(let package, let dependencyURL, let otherDependencyURL, let identity):
            return "'\(package)' dependency on '\(dependencyURL)' conflicts with dependency on '\(otherDependencyURL)' which has the same identity '\(identity)'"

        case .dependencyAlreadySatisfiedByName(let package, let dependencyURL, let otherDependencyURL, let name):
            return "'\(package)' dependency on '\(dependencyURL)' conflicts with dependency on '\(otherDependencyURL)' which has the same explicit name '\(name)'"

        case .productDependencyMissingPackage(
            let productName,
            let targetName,
            let packageIdentifier
        ):

            let solution = """
            reference the package in the target dependency with '.product(name: "\(productName)", package: \
            "\(packageIdentifier)")'
            """

            return "dependency '\(productName)' in target '\(targetName)' requires explicit declaration; \(solution)"

        case .duplicateProduct(let product, let packages):
            return "multiple products named '\(product)' in: '\(packages.joined(separator: "', '"))'"
        case .multipleModuleAliases(let target, let product, let package, let aliases):
            return "multiple aliases: ['\(aliases.joined(separator: "', '"))'] found for target '\(target)' in product '\(product)' from package '\(package)'"
        case .unsupportedPluginDependency(let targetName, let dependencyName, let dependencyType,  let dependencyPackage):
            var trailingMsg = ""
            if let dependencyPackage {
              trailingMsg = " from package '\(dependencyPackage)'"
            }
            return "plugin '\(targetName)' cannot depend on '\(dependencyName)' of type '\(dependencyType)'\(trailingMsg); this dependency is unsupported"
        }
    }
}
