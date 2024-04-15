//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel

@available(*, deprecated, renamed: "ResolvedModule")
public typealias ResolvedTarget = ResolvedModule

/// Represents a fully resolved module. All the dependencies for this module are also stored as resolved.
public struct ResolvedModule {
    /// Represents dependency of a resolved module.
    public enum Dependency {
        /// Direct dependency of the module. The depended on module is in the same package.
        case module(_ module: ResolvedModule, conditions: [PackageCondition])

        @available(*, deprecated, renamed: "module")
        static func target(_ module: ResolvedModule, conditions: [PackageCondition]) -> Self {
            .module(module, conditions: conditions)
        }

        /// The target depends on this product.
        case product(_ product: ResolvedProduct, conditions: [PackageCondition])

        public var module: ResolvedModule? {
            switch self {
            case .module(let module, _): return module
            case .product: return nil
            }
        }

        @available(*, deprecated, renamed: "module")
        public var target: ResolvedModule? {
            self.module
        }

        public var product: ResolvedProduct? {
            switch self {
            case .module: return nil
            case .product(let product, _): return product
            }
        }

        public var conditions: [PackageCondition] {
            switch self {
            case .module(_, let conditions): return conditions
            case .product(_, let conditions): return conditions
            }
        }

        /// Returns the direct dependencies of the underlying dependency, across the package graph.
        public var dependencies: [ResolvedModule.Dependency] {
            switch self {
            case .module(let module, _):
                return module.dependencies
            case .product(let product, _):
                return product.modules.map { .module($0, conditions: []) }
            }
        }

        /// Returns the direct dependencies of the underlying dependency, limited to the module's package.
        public var packageDependencies: [ResolvedModule.Dependency] {
            switch self {
            case .module(let module, _):
                return module.dependencies
            case .product:
                return []
            }
        }

        public func satisfies(_ environment: BuildEnvironment) -> Bool {
            conditions.allSatisfy { $0.satisfies(environment) }
        }
    }

    /// The name of this module.
    public var name: String {
        self.underlying.name
    }

    /// Returns dependencies which satisfy the input build environment, based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func dependencies(satisfying environment: BuildEnvironment) -> [Dependency] {
        return dependencies.filter { $0.satisfies(environment) }
    }

    /// Returns the recursive dependencies, across the whole package-graph.
    public func recursiveDependencies() throws -> [Dependency] {
        try topologicalSort(self.dependencies) { $0.dependencies }
    }


    /// Returns the recursive module dependencies, across the whole package-graph.
    public func recursiveModuleDependencies() throws -> [ResolvedModule] {
        try topologicalSort(self.dependencies) { $0.dependencies }.compactMap { $0.module }
    }

    @available(*, deprecated, renamed: "recursiveModuleDependencies")
    public func recursiveTargetDependencies() throws -> [ResolvedModule] {
        try self.recursiveModuleDependencies()
    }

    /// Returns the recursive dependencies, across the whole package-graph, which satisfy the input build environment,
    /// based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func recursiveDependencies(satisfying environment: BuildEnvironment) throws -> [Dependency] {
        try topologicalSort(dependencies(satisfying: environment)) { dependency in
            dependency.dependencies.filter { $0.satisfies(environment) }
        }
    }

    /// The language-level module name.
    public var c99name: String {
        self.underlying.c99name
    }

    /// Module aliases for dependencies of this module. The key is an
    /// original module name and the value is a new unique name mapped
    /// to the name of its .swiftmodule binary.
    public var moduleAliases: [String: String]? {
        self.underlying.moduleAliases
    }

    /// Allows access to package symbols from other module in the package
    public var packageAccess: Bool {
        self.underlying.packageAccess
    }

    /// The "type" of the module.
    public var type: Target.Kind {
        self.underlying.type
    }

    /// The sources for the module.
    public var sources: Sources {
        self.underlying.sources
    }

    let packageIdentity: PackageIdentity

    /// The underlying module represented in this resolved module.
    public let underlying: Target

    /// The dependencies of this module.
    public let dependencies: [Dependency]

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this module.
    public let supportedPlatforms: [SupportedPlatform]

    private let platformVersionProvider: PlatformVersionProvider

    /// Triple for which this resolved module should be compiled for.
    public let buildTriple: BuildTriple

    /// Create a resolved module instance.
    public init(
        packageIdentity: PackageIdentity,
        underlying: Target,
        dependencies: [ResolvedModule.Dependency],
        defaultLocalization: String? = nil,
        supportedPlatforms: [SupportedPlatform],
        platformVersionProvider: PlatformVersionProvider
    ) {
        self.packageIdentity = packageIdentity
        self.underlying = underlying
        self.dependencies = dependencies
        self.defaultLocalization = defaultLocalization
        self.supportedPlatforms = supportedPlatforms
        self.platformVersionProvider = platformVersionProvider
        self.buildTriple = .destination
    }

    public func getSupportedPlatform(for platform: Platform, usingXCTest: Bool) -> SupportedPlatform {
        self.platformVersionProvider.getDerived(
            declared: self.supportedPlatforms,
            for: platform,
            usingXCTest: usingXCTest
        )
    }
}

extension ResolvedModule: CustomStringConvertible {
    public var description: String {
        return "<ResolvedModule: \(name)>"
    }
}

extension ResolvedModule.Dependency: CustomStringConvertible {
    public var description: String {
        var str = "<ResolvedModule.Dependency: "
        switch self {
        case .product(let p, _):
            str += p.description
        case .module(let m, _):
            str += m.description
        }
        str += ">"
        return str
    }
}

extension ResolvedModule.Dependency: Identifiable {
    public struct ID: Hashable {
        enum Kind: Hashable {
            case module
            case product

            @available(*, deprecated, renamed: "module")
            public static let target: Kind = .module
        }

        let kind: Kind
        let packageIdentity: PackageIdentity
        let name: String
    }

    public var id: ID {
        switch self {
        case .module(let module, _):
            return .init(kind: .module, packageIdentity: module.packageIdentity, name: module.name)
        case .product(let product, _):
            return .init(kind: .product, packageIdentity: product.packageIdentity, name: product.name)
        }
    }
}

extension ResolvedModule.Dependency: Equatable {
    public static func == (lhs: ResolvedModule.Dependency, rhs: ResolvedModule.Dependency) -> Bool {
        switch (lhs, rhs) {
        case (.module(let lhsModule, _), .module(let rhsModule, _)):
            return lhsModule.id == rhsModule.id
        case (.product(let lhsProduct, _), .product(let rhsProduct, _)):
            return lhsProduct.id == rhsProduct.id
        case (.product, .module), (.module, .product):
            return false
        }
    }
}

extension ResolvedModule.Dependency: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .module(let module, _):
            hasher.combine(module.id)
        case .product(let product, _):
            hasher.combine(product.id)
        }
    }
}

extension ResolvedModule: Identifiable {
    /// Resolved module identity that uniquely identifies it in a resolution graph.
    public struct ID: Hashable {
        @available(*, deprecated, renamed: "moduleName")
        public var targetName: String { self.moduleName }

        public let moduleName: String
        let packageIdentity: PackageIdentity
        public let buildTriple: BuildTriple
    }

    public var id: ID {
        ID(moduleName: self.name, packageIdentity: self.packageIdentity, buildTriple: self.buildTriple)
    }
}

@available(*, unavailable, message: "Use `Identifiable` conformance or `IdentifiableSet` instead")
extension ResolvedModule: Hashable {}
