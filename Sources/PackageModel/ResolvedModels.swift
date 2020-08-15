/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// Represents a fully resolved target. All the dependencies for the target are resolved.
public final class ResolvedTarget: CustomStringConvertible, ObjectIdentifierProtocol {

    /// Represents dependency of a resolved target.
    public enum Dependency: Hashable {
        public static func == (lhs: ResolvedTarget.Dependency, rhs: ResolvedTarget.Dependency) -> Bool {
            switch (lhs, rhs) {
            case (.target(let lhsTarget, _), .target(let rhsTarget, _)):
                return lhsTarget == rhsTarget
            case (.product(let lhsProduct, _), .product(let rhsProduct, _)):
                return lhsProduct == rhsProduct
            case (.product, .target), (.target, .product):
                return false
            }
        }

        /// Direct dependency of the target. This target is in the same package and should be statically linked.
        case target(_ target: ResolvedTarget, conditions: [PackageConditionProtocol])

        /// The target depends on this product.
        case product(_ product: ResolvedProduct, conditions: [PackageConditionProtocol])

        public var target: ResolvedTarget? {
            switch self {
            case .target(let target, _): return target
            case .product: return nil
            }
        }

        public var product: ResolvedProduct? {
            switch self {
            case .target: return nil
            case .product(let product, _): return product
            }
        }

        public var conditions: [PackageConditionProtocol] {
            switch self {
            case .target(_, let conditions): return conditions
            case .product(_, let conditions): return conditions
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .target(let target, _):
                hasher.combine(target)
            case .product(let product, _):
                hasher.combine(product)
            }
        }

        public func satisfies(_ environment: BuildEnvironment) -> Bool {
            conditions.allSatisfy { $0.satisfies(environment) }
        }
    }

    /// The underlying target represented in this resolved target.
    public let underlyingTarget: Target

    /// The name of this target.
    public var name: String {
        return underlyingTarget.name
    }

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// Returns dependencies which satisfy the input build environment, based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func dependencies(satisfying environment: BuildEnvironment) -> [Dependency] {
        return dependencies.filter { $0.satisfies(environment) }
    }

    /// Returns the recursive dependencies, accross the whole package-graph.
    public func recursiveDependencies() -> [Dependency] {
        return try! topologicalSort(self.dependencies) { $0.dependencies }
    }

    /// Returns the recursive target dependencies, accross the whole package-graph.
    public func recursiveTargetDependencies() -> [ResolvedTarget] {
        return try! topologicalSort(self.dependencies) { $0.dependencies }.compactMap { $0.target }
    }

    /// Returns the recursive dependencies, accross the whole package-graph, which satisfy the input build environment,
    /// based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func recursiveDependencies(satisfying environment: BuildEnvironment) -> [Dependency] {
        return try! topologicalSort(dependencies(satisfying: environment)) { dependency in
            return dependency.dependencies.filter { $0.satisfies(environment) }
        }
    }

    /// The language-level target name.
    public var c99name: String {
        return underlyingTarget.c99name
    }

    /// The "type" of target.
    public var type: Target.Kind {
        return underlyingTarget.type
    }

    /// The sources for the target.
    public var sources: Sources {
        return underlyingTarget.sources
    }

    /// Create a target instance.
    public init(target: Target, dependencies: [Dependency]) {
        self.underlyingTarget = target
        self.dependencies = dependencies
    }

    public var description: String {
        return "<ResolvedTarget: \(name)>"
    }
}

/// A fully resolved package. Contains resolved targets, products and dependencies of the package.
public final class ResolvedPackage: CustomStringConvertible, ObjectIdentifierProtocol {

    /// The underlying package reference.
    public let underlyingPackage: Package

    /// The manifest describing the package.
    public var manifest: Manifest {
        return underlyingPackage.manifest
    }

    /// The name of the package.
    public var name: String {
        return underlyingPackage.name
    }

    /// The local path of the package.
    public var path: AbsolutePath {
        return underlyingPackage.path
    }

    /// The targets contained in the package.
    public let targets: [ResolvedTarget]

    /// The products produced by the package.
    public let products: [ResolvedProduct]

    /// The dependencies of the package.
    public let dependencies: [ResolvedPackage]

    public init(
        package: Package,
        dependencies: [ResolvedPackage],
        targets: [ResolvedTarget],
        products: [ResolvedProduct]
    ) {
        self.underlyingPackage = package
        self.dependencies = dependencies
        self.targets = targets
        self.products = products
    }

    public var description: String {
        return "<ResolvedPackage: \(name)>"
    }
}

public final class ResolvedProduct: ObjectIdentifierProtocol, CustomStringConvertible {

    /// The underlying product.
    public let underlyingProduct: Product

    /// The name of this product.
    public var name: String {
        return underlyingProduct.name
    }

    /// The top level targets contained in this product.
    public let targets: [ResolvedTarget]

    /// The type of this product.
    public var type: ProductType {
        return underlyingProduct.type
    }

    /// Executable target for linux main test manifest file.
    public let linuxMainTarget: ResolvedTarget?

    /// The main executable target of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableModule: ResolvedTarget {
        precondition(type == .executable, "This property should only be called for executable targets")
        return targets.first(where: { $0.type == .executable })!
    }

    public init(product: Product, targets: [ResolvedTarget]) {
        assert(product.targets.count == targets.count && product.targets.map({ $0.name }) == targets.map({ $0.name }))
        self.underlyingProduct = product
        self.targets = targets

        self.linuxMainTarget = underlyingProduct.linuxMain.map({ linuxMain in
            // Create an executable resolved target with the linux main, adding product's targets as dependencies.
            let dependencies: [Target.Dependency] = product.targets.map { .target($0, conditions: []) }
            let swiftTarget = SwiftTarget(linuxMain: linuxMain, name: product.name, dependencies: dependencies)
            return ResolvedTarget(target: swiftTarget, dependencies: targets.map { .target($0, conditions: []) })
        })
    }

    public var description: String {
        return "<ResolvedProduct: \(name)>"
    }

    /// True if this product contains Swift targets.
    public var containsSwiftTargets: Bool {
      //  C targets can't import Swift targets in SwiftPM (at least not right
      // now), so we can just look at the top-level targets.
      //
      // If that ever changes, we'll need to do something more complex here,
      // recursively checking dependencies for SwiftTargets, and considering
      // dynamic library targets to be Swift targets (since the dylib could
      // contain Swift code we don't know about as part of this build).
      return targets.contains { $0.underlyingTarget is SwiftTarget }
    }

    /// Returns the recursive target dependencies.
    public func recursiveTargetDependencies() -> [ResolvedTarget] {
        let recursiveDependencies = targets.lazy.flatMap { $0.recursiveTargetDependencies() }
        return Array(Set(targets).union(recursiveDependencies))
    }
}

extension ResolvedTarget.Dependency: CustomStringConvertible {

    /// Returns the direct dependencies of the underlying dependency, accross the package graph.
    public var dependencies: [ResolvedTarget.Dependency] {
        switch self {
        case .target(let target, _):
            return target.dependencies
        case .product(let product, _):
            return product.targets.map { .target($0, conditions: []) }
        }
    }

    /// Returns the direct dependencies of the underlying dependency, limited to the target's package.
    public var packageDependencies: [ResolvedTarget.Dependency] {
        switch self {
        case .target(let target, _):
            return target.dependencies
        case .product:
            return []
        }
    }

    // MARK: - CustomStringConvertible conformance

    public var description: String {
        var str = "<ResolvedTarget.Dependency: "
        switch self {
        case .product(let p, _):
            str += p.description
        case .target(let t, _):
            str += t.description
        }
        str += ">"
        return str
    }
}
