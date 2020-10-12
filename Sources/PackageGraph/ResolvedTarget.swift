/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

/// Represents a fully resolved target. All the dependencies for the target are resolved.
public final class ResolvedTarget: ObjectIdentifierProtocol {

    /// Represents dependency of a resolved target.
    public enum Dependency {
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
}

extension ResolvedTarget: CustomStringConvertible {
    public var description: String {
        return "<ResolvedTarget: \(name)>"
    }
}

extension ResolvedTarget.Dependency: Equatable {
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
}

extension ResolvedTarget.Dependency: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .target(let target, _):
            hasher.combine(target)
        case .product(let product, _):
            hasher.combine(product)
        }
    }
}

extension ResolvedTarget.Dependency: CustomStringConvertible {
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
