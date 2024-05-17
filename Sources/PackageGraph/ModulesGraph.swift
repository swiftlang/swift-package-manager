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

import struct Basics.IdentifiableSet
import OrderedCollections
import PackageLoading
import PackageModel

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no targets.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case dependencyCycleDetected(path: [Manifest], cycle: Manifest)

    /// The product dependency not found.
    case productDependencyNotFound(package: String, targetName: String, dependencyProductName: String, dependencyPackageName: String?, dependencyProductInDecl: Bool, similarProductName: String?, packageContainingSimilarProduct: String?)

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
    case duplicateProduct(product: String, packages: [Package])

    /// Duplicate aliases for a target found in a product.
    case multipleModuleAliases(target: String,
                               product: String,
                               package: String,
                               aliases: [String])
}

@available(*,
    deprecated,
    renamed: "ModulesGraph",
    message: "PackageGraph had a misleading name, it's a graph of dependencies between modules, not just packages"
)
public typealias PackageGraph = ModulesGraph

/// A collection of packages.
public struct ModulesGraph {
    /// The root packages.
    public let rootPackages: IdentifiableSet<ResolvedPackage>

    /// The complete set of contained packages.
    public let packages: IdentifiableSet<ResolvedPackage>

    /// The list of all targets reachable from root targets.
    public private(set) var reachableTargets: IdentifiableSet<ResolvedModule>

    /// The list of all products reachable from root targets.
    public private(set) var reachableProducts: IdentifiableSet<ResolvedProduct>

    /// Returns all the targets in the graph, regardless if they are reachable from the root targets or not.
    public private(set) var allTargets: IdentifiableSet<ResolvedModule>

    /// Returns all targets within the module graph in topological order, starting with low-level targets (that have no
    /// dependencies).
    package var allTargetsInTopologicalOrder: [ResolvedTarget] {
        get throws {
            try topologicalSort(Array(allTargets)) { $0.dependencies.compactMap { $0.target } }.reversed()
        }
    }

    /// Returns all the products in the graph, regardless if they are reachable from the root targets or not.
    public private(set) var allProducts: IdentifiableSet<ResolvedProduct>

    /// Package dependencies required for a fully resolved graph.
    ///
    /// This will include a references to dependencies that are currently present
    /// in the graph due to loading errors. This does not include the root packages.
    public let requiredDependencies: [PackageReference]

    /// Returns true if a given target is present in root packages and is not excluded for the given build environment.
    public func isInRootPackages(_ target: ResolvedModule, satisfying buildEnvironment: BuildEnvironment) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.reduce(
            into: IdentifiableSet<ResolvedModule>()
        ) { (accumulator: inout IdentifiableSet<ResolvedModule>, package: ResolvedPackage) in
            let allDependencies = package.targets.flatMap { $0.dependencies }
            let unsatisfiedDependencies = allDependencies.filter { !$0.satisfies(buildEnvironment) }
            let unsatisfiedDependencyTargets = unsatisfiedDependencies.compactMap { (
                dep: ResolvedModule.Dependency
            ) -> ResolvedModule? in
                switch dep {
                case .target(let target, _):
                    return target
                default:
                    return nil
                }
            }

            accumulator.formUnion(IdentifiableSet(package.targets).subtracting(unsatisfiedDependencyTargets))
        }.contains(id: target.id)
    }

    public func isRootPackage(_ package: ResolvedPackage) -> Bool {
        // FIXME: This can be easily cached.
        return self.rootPackages.contains(id: package.id)
    }

    /// Returns the package  based on the given identity, or nil if the package isn't in the graph.
    public func package(for identity: PackageIdentity) -> ResolvedPackage? {
        packages[identity]
    }

    /// Returns the package that contains the module, or nil if the module isn't in the graph.
    public func package(for module: ResolvedModule) -> ResolvedPackage? {
        self.package(for: module.packageIdentity)
    }

    /// Returns the package that contains the product, or nil if the product isn't in the graph.
    public func package(for product: ResolvedProduct) -> ResolvedPackage? {
        self.package(for: product.packageIdentity)
    }

    /// Returns all of the packages that the given package depends on directly.
    public func directDependencies(for package: ResolvedPackage) -> [ResolvedPackage] {
        package.dependencies.compactMap { self.package(for: $0) }
    }

    public func product(for name: String, destination: BuildTriple) -> ResolvedProduct? {
        self.allProducts.first { $0.name == name && $0.buildTriple == destination }
    }

    public func target(for name: String, destination: BuildTriple) -> ResolvedModule? {
        self.allTargets.first { $0.name == name && $0.buildTriple == destination }
    }

    /// All root and root dependency packages provided as input to the graph.
    public let inputPackages: [ResolvedPackage]

    /// Any binary artifacts referenced by the graph.
    public let binaryArtifacts: [PackageIdentity: [String: BinaryArtifact]]

    /// Construct a package graph directly.
    public init(
        rootPackages: [ResolvedPackage],
        rootDependencies: [ResolvedPackage] = [],
        packages: IdentifiableSet<ResolvedPackage>,
        dependencies requiredDependencies: [PackageReference],
        binaryArtifacts: [PackageIdentity: [String: BinaryArtifact]]
    ) throws {
        let rootPackages = IdentifiableSet(rootPackages)
        self.requiredDependencies = requiredDependencies
        self.inputPackages = rootPackages + rootDependencies
        self.binaryArtifacts = binaryArtifacts
        self.packages = packages

        var allTargets = IdentifiableSet<ResolvedModule>()
        var allProducts = IdentifiableSet<ResolvedProduct>()
        for package in self.packages {
            let targetsToInclude: [ResolvedModule]
            if rootPackages.contains(id: package.id) {
                targetsToInclude = Array(package.targets)
            } else {
                // Don't include tests targets from non-root packages so swift-test doesn't
                // try to run them.
                targetsToInclude = package.targets.filter { $0.type != .test }
            }

            for target in targetsToInclude {
                allTargets.insert(target)

                // Explicitly include dependencies of host tools in the maps of all targets or all products
                if target.buildTriple == .tools {
                    for dependency in try target.recursiveDependencies() {
                        switch dependency {
                        case .target(let targetDependency, _):
                            allTargets.insert(targetDependency)
                        case .product(let productDependency, _):
                            allProducts.insert(productDependency)
                        }
                    }
                }

                // Create a new executable product if plugin depends on an executable target.
                // This is necessary, even though PackageBuilder creates one already, because
                // that product is going to be built for `destination`, and this one has to
                // be built for `tools`.
                if target.underlying is PluginTarget {
                    for dependency in target.dependencies {
                        switch dependency {
                        case .product(_, conditions: _):
                            break

                        case .target(let target, conditions: _):
                            if target.type != .executable {
                                continue
                            }

                            var product = try ResolvedProduct(
                                packageIdentity: target.packageIdentity,
                                product: .init(
                                    package: target.packageIdentity,
                                    name: target.name,
                                    type: .executable,
                                    targets: [target.underlying]
                                ),
                                targets: IdentifiableSet([target])
                            )
                            product.buildTriple = .tools

                            allProducts.insert(product)
                        }
                    }
                }
            }

            if rootPackages.contains(id: package.id) {
                allProducts.formUnion(package.products)
            } else {
                // Don't include test products from non-root packages so swift-test doesn't
                // try to run them.
                allProducts.formUnion(package.products.filter { $0.type != .test })
            }
        }

        // Compute the reachable targets and products.
        let inputTargets = self.inputPackages.flatMap { $0.targets }
        let inputProducts = self.inputPackages.flatMap { $0.products }
        let recursiveDependencies = try inputTargets.lazy.flatMap { try $0.recursiveDependencies() }

        self.reachableTargets = IdentifiableSet(inputTargets).union(recursiveDependencies.compactMap { $0.target })
        self.reachableProducts = IdentifiableSet(inputProducts).union(recursiveDependencies.compactMap { $0.product })
        self.rootPackages = rootPackages
        self.allTargets = allTargets
        self.allProducts = allProducts
    }

    /// Computes a map from each executable target in any of the root packages to the corresponding test targets.
    func computeTestTargetsForExecutableTargets() throws -> [ResolvedModule.ID: [ResolvedModule]] {
        var result = [ResolvedModule.ID: [ResolvedModule]]()

        let rootTargets = IdentifiableSet(rootPackages.flatMap { $0.targets })

        // Create map of test target to set of its direct dependencies.
        let testTargetDepMap: [ResolvedModule.ID: IdentifiableSet<ResolvedModule>] = try {
            let testTargetDeps = rootTargets.filter({ $0.type == .test }).map({
                ($0.id, IdentifiableSet($0.dependencies.compactMap { $0.target }.filter { $0.type != .plugin }))
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

            result[target.id] = testTargets.compactMap { rootTargets[$0] }
        }

        return result
    }
}

extension PackageGraphError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noModules(let package):
            return "package '\(package)' contains no products"

        case .dependencyCycleDetected(let path, let package):
            return "cyclic dependency between packages " +
            (path.map({ $0.displayName }).joined(separator: " -> ")) +
            " -> \(package.displayName) requires tools-version 6.0 or later"

        case .productDependencyNotFound(let package, let targetName, let dependencyProductName, let dependencyPackageName, let dependencyProductInDecl, let similarProductName, let packageContainingSimilarProduct):
            if dependencyProductInDecl {
                return "product '\(dependencyProductName)' is declared in the same package '\(package)' and can't be used as a dependency for target '\(targetName)'."
            } else {
                var description = "product '\(dependencyProductName)' required by package '\(package)' target '\(targetName)' \(dependencyPackageName.map{ "not found in package '\($0)'" } ?? "not found")."
                if let similarProductName, let packageContainingSimilarProduct {
                    description += " Did you mean '.product(name: \"\(similarProductName)\", package: \"\(packageContainingSimilarProduct)\")'?"
                } else if let similarProductName {
                    description += " Did you mean '\(similarProductName)'?"
                }
                return description
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
            let packagesDescriptions = packages.sorted(by: { $0.identity < $1.identity }).map {
                var description = "'\($0.identity)'"
                switch $0.manifest.packageKind {
                case .root(let path),
                        .fileSystem(let path),
                        .localSourceControl(let path):
                    description += " (at '\(path)')"
                case .remoteSourceControl(let url):
                    description += " (from '\(url)')"
                case .registry:
                    break
                }
                return description
            }
            return "multiple packages (\(packagesDescriptions.joined(separator: ", "))) declare products with a conflicting name: '\(product)’; product names need to be unique across the package graph"
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

enum GraphError: Error {
    /// A cycle was detected in the input.
    case unexpectedCycle
}

/// Perform a topological sort of an graph.
///
/// This function is optimized for use cases where cycles are unexpected, and
/// does not attempt to retain information on the exact nodes in the cycle.
///
/// - Parameters:
///   - nodes: The list of input nodes to sort.
///   - successors: A closure for fetching the successors of a particular node.
///
/// - Returns: A list of the transitive closure of nodes reachable from the
/// inputs, ordered such that every node in the list follows all of its
/// predecessors.
///
/// - Throws: GraphError.unexpectedCycle
///
/// - Complexity: O(v + e) where (v, e) are the number of vertices and edges
/// reachable from the input nodes via the relation.
func topologicalSort<T: Identifiable>(
    _ nodes: [T], successors: (T) throws -> [T]
) throws -> [T] {
    // Implements a topological sort via recursion and reverse postorder DFS.
    func visit(_ node: T,
               _ stack: inout OrderedSet<T.ID>, _ visited: inout Set<T.ID>, _ result: inout [T],
               _ successors: (T) throws -> [T]) throws {
        // Mark this node as visited -- we are done if it already was.
        if !visited.insert(node.id).inserted {
            return
        }

        // Otherwise, visit each adjacent node.
        for succ in try successors(node) {
            guard stack.append(succ.id).inserted else {
                // If the successor is already in this current stack, we have found a cycle.
                //
                // FIXME: We could easily include information on the cycle we found here.
                throw GraphError.unexpectedCycle
            }
            try visit(succ, &stack, &visited, &result, successors)
            let popped = stack.removeLast()
            assert(popped == succ.id)
        }

        // Add to the result.
        result.append(node)
    }

    // FIXME: This should use a stack not recursion.
    var visited = Set<T.ID>()
    var result = [T]()
    var stack = OrderedSet<T.ID>()
    for node in nodes {
        precondition(stack.isEmpty)
        stack.append(node.id)
        try visit(node, &stack, &visited, &result, successors)
        let popped = stack.removeLast()
        assert(popped == node.id)
    }

    return result.reversed()
}
