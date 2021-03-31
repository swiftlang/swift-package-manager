/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import PackageModel

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no targets.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case cycleDetected((path: [Manifest], cycle: [Manifest]))

    /// The product dependency not found.
    case productDependencyNotFound(package: String, targetName: String, dependencyProductName: String, dependencyPackageName: String?)

    /// The package dependency name does not match the package name.
    case incorrectPackageDependencyName(package: String, dependencyName: String, dependencyLocation: String, resolvedPackageManifestName: String, resolvedPackageURL: String)

    /// The package dependency already satisfied by a different dependency package
    case dependencyAlreadySatisfiedByIdentifier(package: String, dependencyLocation: String, otherDependencyURL: String, identity: PackageIdentity)

    /// The package dependency already satisfied by a different dependency package
    case dependencyAlreadySatisfiedByName(package: String, dependencyLocation: String, otherDependencyURL: String, name: String)

    /// The product dependency was found but the package name was not referenced correctly (tools version > 5.2).
    case productDependencyMissingPackage(
        productName: String,
        targetName: String,
        packageDependency: PackageDependencyDescription
    )

    /// A product was found in multiple packages.
    case duplicateProduct(product: String, packages: [String])
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

    /// Returns true if a given target is present in root packages.
    public func isInRootPackages(_ target: ResolvedTarget) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.flatMap({ $0.targets }).contains(target)
    }

    public func isRootPackage(_ package: ResolvedPackage) -> Bool {
        // FIXME: This can be easily cached.
        return rootPackages.contains(package)
    }

    /// Returns the package that contains the target, or nil if the target isn't in the graph.
    public func package(for target: ResolvedTarget) -> ResolvedPackage? {
        return self.targetsToPackages[target]
    }
    private let targetsToPackages: [ResolvedTarget: ResolvedPackage]

    /// Returns the package that contains the product, or nil if the product isn't in the graph.
     public func package(for product: ResolvedProduct) -> ResolvedPackage? {
         return self.productsToPackages[product]
     }
    private let productsToPackages: [ResolvedProduct: ResolvedPackage]

    /// All root and root dependency packages provided as input to the graph.
    public let inputPackages: [ResolvedPackage]

    /// Construct a package graph directly.
    public init(
        rootPackages: [ResolvedPackage],
        rootDependencies: [ResolvedPackage] = [],
        dependencies requiredDependencies: Set<PackageReference>
    ) throws {
        self.rootPackages = rootPackages
        self.requiredDependencies = requiredDependencies
        self.inputPackages = rootPackages + rootDependencies
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
        let testTargetDepMap: [ResolvedTarget: Set<ResolvedTarget>] = {
            let testTargetDeps = rootTargets.filter({ $0.type == .test }).map({
                ($0, Set($0.dependencies.compactMap({ $0.target })))
            })
            return Dictionary(uniqueKeysWithValues: testTargetDeps)
        }()

        for target in rootTargets where target.type == .executable {
            // Find all dependencies of this target within its package.
            let dependencies = try topologicalSort(target.dependencies, successors: {
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

extension PackageGraphError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noModules(let package):
            return "package '\(package)' contains no products"

        case .cycleDetected(let cycle):
            return "cyclic dependency declaration found: " +
                (cycle.path + cycle.cycle).map({ $0.name }).joined(separator: " -> ") +
                " -> " + cycle.cycle[0].name

        case .productDependencyNotFound(let package, let targetName, let dependencyProductName, let dependencyPackageName):
            return "product '\(dependencyProductName)' required by package '\(package)' target '\(targetName)' \(dependencyPackageName.map{ "not found in package '\($0)'" } ?? "not found")."

        case .incorrectPackageDependencyName(let package, let dependencyName, let dependencyURL, let resolvedPackageManifestName, let resolvedPackageURL):
            return """
                '\(package)' dependency on '\(dependencyURL)' has an explicit name '\(dependencyName)' which does not match the \
                name '\(resolvedPackageManifestName)' set for '\(resolvedPackageURL)'
                """

        case .dependencyAlreadySatisfiedByIdentifier(let package, let dependencyURL, let otherDependencyURL, let identity):
            return "'\(package)' dependency on '\(dependencyURL)' conflicts with dependency on '\(otherDependencyURL)' which has the same identity '\(identity)'"

        case .dependencyAlreadySatisfiedByName(let package, let dependencyURL, let otherDependencyURL, let name):
            return "'\(package)' dependency on '\(dependencyURL)' conflicts with dependency on '\(otherDependencyURL)' which has the same explicit name '\(name)'"

        case .productDependencyMissingPackage(
                let productName,
                let targetName,
                let packageDependency
            ):

            let solution = """
            reference the package in the target dependency with '.product(name: "\(productName)", package: \
            "\(packageDependency.nameForTargetDependencyResolutionOnly)")'
            """

            return "dependency '\(productName)' in target '\(targetName)' requires explicit declaration; \(solution)"

        case .duplicateProduct(let product, let packages):
            return "multiple products named '\(product)' in: '\(packages.joined(separator: "', '"))'"
        }
    }
}

fileprivate extension PackageDependencyDescription {
    func swiftRepresentation(overridingName: String? = nil) -> String {
        var parameters: [String] = []

        if let name = overridingName ?? self.explicitNameForTargetDependencyResolutionOnly {
            parameters.append("name: \"\(name)\"")
        }

        switch self {
        case .local(let data):
            parameters.append("path: \"\(data.path)\"")
        case .scm(let data):
            parameters.append("url: \"\(data.location)\"")
            switch data.requirement {
            case .branch(let branch):
                parameters.append(".branch(\"\(branch)\")")
            case .exact(let version):
                parameters.append(".exact(\"\(version)\")")
            case .revision(let revision):
                parameters.append(".revision(\"\(revision)\")")
            case .range(let range):
                if range.upperBound == Version(range.lowerBound.major + 1, 0, 0) {
                    parameters.append("from: \"\(range.lowerBound)\"")
                } else if range.upperBound == Version(range.lowerBound.major, range.lowerBound.minor + 1, 0) {
                    parameters.append(".upToNextMinor(\"\(range.lowerBound)\")")
                } else {
                    parameters.append(".upToNextMinor(\"\(range.lowerBound)\"..<\"\(range.upperBound)\")")
                }
            }
        }

        let swiftRepresentation = ".package(\(parameters.joined(separator: ", ")))"
        return swiftRepresentation
    }
}
