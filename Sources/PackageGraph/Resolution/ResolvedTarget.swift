//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel

import func TSCBasic.topologicalSort

/// Represents a fully resolved target. All the dependencies for the target are resolved.
public struct ResolvedTarget: Hashable {
    /// Represents dependency of a resolved target.
    public enum Dependency: Hashable {
        /// Direct dependency of the target. This target is in the same package and should be statically linked.
        case target(_ target: ResolvedTarget, conditions: [PackageCondition])

        /// The target depends on this product.
        case product(_ product: ResolvedProduct, conditions: [PackageCondition])

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

        public var conditions: [PackageCondition] {
            switch self {
            case .target(_, let conditions): return conditions
            case .product(_, let conditions): return conditions
            }
        }

        /// Returns the direct dependencies of the underlying dependency, across the package graph.
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

    /// The name of this target.
    public var name: String {
        return underlying.name
    }

    /// Returns dependencies which satisfy the input build environment, based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func dependencies(satisfying environment: BuildEnvironment) -> [Dependency] {
        return dependencies.filter { $0.satisfies(environment) }
    }

    /// Returns the recursive dependencies, across the whole package-graph.
    public func recursiveDependencies() throws -> [Dependency] {
        return try topologicalSort(self.dependencies) { $0.dependencies }
    }

    /// Returns the recursive target dependencies, across the whole package-graph.
    public func recursiveTargetDependencies() throws -> [ResolvedTarget] {
        return try topologicalSort(self.dependencies) { $0.dependencies }.compactMap { $0.target }
    }

    /// Returns the recursive dependencies, across the whole package-graph, which satisfy the input build environment,
    /// based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func recursiveDependencies(satisfying environment: BuildEnvironment) throws -> [Dependency] {
        return try topologicalSort(dependencies(satisfying: environment)) { dependency in
            return dependency.dependencies.filter { $0.satisfies(environment) }
        }
    }

    /// The language-level target name.
    public var c99name: String {
        return underlying.c99name
    }

    /// Module aliases for dependencies of this target. The key is an
    /// original target name and the value is a new unique name mapped
    /// to the name of its .swiftmodule binary.
    public var moduleAliases: [String: String]? {
      return underlying.moduleAliases
    }

    /// Allows access to package symbols from other targets in the package
    public var packageAccess: Bool {
        return underlying.packageAccess
    }

    /// The "type" of target.
    public var type: Target.Kind {
        return underlying.type
    }

    /// The sources for the target.
    public var sources: Sources {
        return underlying.sources
    }

    /// The underlying target represented in this resolved target.
    public let underlying: Target

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this target.
    public let supportedPlatforms: [SupportedPlatform]

    private let platformVersionProvider: PlatformVersionProvider

    public init(
        underlying: Target,
        dependencies: [ResolvedTarget.Dependency],
        defaultLocalization: String? = nil,
        supportedPlatforms: [SupportedPlatform],
        platformVersionProvider: PlatformVersionProvider
    ) {
        self.underlying = underlying
        self.dependencies = dependencies
        self.defaultLocalization = defaultLocalization
        self.supportedPlatforms = supportedPlatforms
        self.platformVersionProvider = platformVersionProvider
    }


    public func getDerived(for platform: Platform, usingXCTest: Bool) -> SupportedPlatform {
        self.platformVersionProvider.getDerived(
            declared: self.supportedPlatforms,
            for: platform,
            usingXCTest: usingXCTest
        )
    }
}

extension ResolvedTarget: CustomStringConvertible {
    public var description: String {
        return "<ResolvedTarget: \(name)>"
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
