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

import func TSCBasic.topologicalSort
import struct Basics.IdentifiableSet

@available(*, deprecated, renamed: "ResolvedModule")
public typealias ResolvedTarget = ResolvedModule

/// Represents a fully resolved module. All the dependencies for this module are also stored as resolved.
public struct ResolvedModule {
    /// Represents dependency of a resolved module.
    public enum Dependency {
        /// Direct dependency of the module. This module is in the same package and should be statically linked.
        case module(_ module: ResolvedModule, conditions: [PackageCondition])

        /// The module depends on this product.
        case product(_ product: ResolvedProduct, conditions: [PackageCondition])

        public var module: ResolvedModule? {
            switch self {
            case .module(let module, _): return module
            case .product: return nil
            }
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

    /// Represents a plugin usage of a resolved module.
    public enum PluginUsage: Hashable {

        /// A plugin defined as a module in the same package, with an optional condition.
        case module(_ module: ResolvedModule, condition: Module.PluginUsageCondition?)

        /// A plugin defined as a product in a package dependency, with an optional condition.
        case product(_ product: ResolvedProduct, condition: Module.PluginUsageCondition?)

        /// The condition under which the plugin is applied, if any.
        public var condition: Module.PluginUsageCondition? {
            switch self {
            case .module(_, let condition), .product(_, let condition):
                condition
            }
        }

        /// The name of the plugin module or product.
        public var name: String {
            switch self {
            case .module(let module, _):
                module.name
            case .product(let product, _):
                product.name
            }
        }

        /// The build-tool plugin module(s) referenced by this usage. A direct `.module`
        /// usage yields at most one module (the empty array if the referenced module isn't
        /// a build-tool plugin); a `.product` usage yields every plugin module reachable
        /// through the product. Used everywhere a caller needs to enumerate plugins from
        /// a `PluginUsage` without re-implementing the dispatch.
        public var buildToolPluginModules: [ResolvedModule] {
            switch self {
            case .module(let module, _):
                if (module.underlying as? PluginModule)?.capability == .buildTool {
                    return [module]
                }
                return []
            case .product(let product, _):
                return product.modules.filter { $0.underlying is PluginModule }
            }
        }

        /// Returns true if the condition is satisfied by the given build environments and enabled traits.
        public func satisfies(hostEnvironment: BuildEnvironment, targetEnvironment: BuildEnvironment, enabledTraits: EnabledTraits) -> Bool {
            guard let condition else {
                return true
            }
            return condition.satisfies(
                hostEnvironment: hostEnvironment,
                targetEnvironment: targetEnvironment,
                enabledTraits: enabledTraits
            )
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

    /// Returns the recursive dependencies, across the whole modules graph, which satisfy the input build environment,
    /// based on their conditions.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func recursiveDependencies(satisfying environment: BuildEnvironment) throws -> [Dependency] {
        try topologicalSort(dependencies(satisfying: environment)) { dependency in
            dependency.dependencies.filter { $0.satisfies(environment) }
        }
    }

    /// Collect all of the plugins that the current target depends on.
    package func pluginDependencies(
        satisfying hostEnvironment: BuildEnvironment,
        targetEnvironment: BuildEnvironment,
        enabledTraits: EnabledTraits
    ) -> [ResolvedModule] {
        var plugins = IdentifiableSet<ResolvedModule>()
        for usage in self.pluginUsages where usage.satisfies(
            hostEnvironment: hostEnvironment,
            targetEnvironment: targetEnvironment,
            enabledTraits: enabledTraits
        ) {
            switch usage {
            case .module(let module, _):
                if let plugin = module.underlying as? PluginModule {
                    assert(plugin.capability == .buildTool)
                    plugins.insert(module)
                }
            case .product(let product, _):
                for plugin in product.modules.filter({ $0.underlying is PluginModule }) {
                    plugins.insert(plugin)
                }
            }
        }
        return Array(plugins)
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

    /// Allows access to package symbols from other modules in the package
    public var packageAccess: Bool {
        self.underlying.packageAccess
    }

    /// The "type" of the module.
    public var type: Module.Kind {
        self.underlying.type
    }

    /// The sources for the module.
    public var sources: Sources {
        self.underlying.sources
    }

    package let packageIdentity: PackageIdentity

    /// The underlying module represented in this resolved module.
    public let underlying: Module

    /// The dependencies of this module.
    public internal(set) var dependencies: [Dependency]

    /// The plugin usages of this module.
    public let pluginUsages: [PluginUsage]

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this module.
    public let supportedPlatforms: [SupportedPlatform]

    /// A constraint on which platforms this module needs to build for.
    /// Note: currently only set to .host if prebuilts are enabled.
    public let platformConstraint: PlatformConstraint

    /// True if this is a test module that is directly depended upon by other test modules
    /// in the same package.
    package let isTestSupportModule: Bool

    @_spi(SwiftPMInternal)
    public let platformVersionProvider: PlatformVersionProvider

    package var hasDirectMacroDependencies: Bool {
        self.dependencies.contains(where: {
            switch $0 {
            case .product(let productDependency, _):
                productDependency.type == .macro
            case .module(let moduleDependency, _):
                moduleDependency.type == .macro
            }
        })
    }

    /// Whether this module comes from a declaration in the manifest file
    /// or was synthesized (i.e. some test modules are synthesized).
    public var implicit: Bool {
        self.underlying.implicit
    }

    /// Create a resolved module instance.
    public init(
        packageIdentity: PackageIdentity,
        underlying: Module,
        dependencies: [ResolvedModule.Dependency],
        pluginUsages: [ResolvedModule.PluginUsage] = [],
        defaultLocalization: String? = nil,
        supportedPlatforms: [SupportedPlatform],
        platformConstraint: PlatformConstraint,
        platformVersionProvider: PlatformVersionProvider,
        isTestSupportModule: Bool = false
    ) {
        self.packageIdentity = packageIdentity
        self.underlying = underlying
        self.dependencies = dependencies
        self.pluginUsages = pluginUsages
        self.defaultLocalization = defaultLocalization
        self.supportedPlatforms = supportedPlatforms
        self.platformConstraint = platformConstraint
        self.platformVersionProvider = platformVersionProvider
        self.isTestSupportModule = isTestSupportModule
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
        return "<ResolvedModule: \(self.name), \(self.type)>"
    }
}

extension ResolvedModule.Dependency: CustomStringConvertible {
    public var description: String {
        var str = "<ResolvedModule.Dependency: "
        switch self {
        case .product(let p, _):
            str += p.description
        case .module(let t, _):
            str += t.description
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
    /// Resolved module identity that uniquely identifies it in a modules graph.
    public struct ID: Hashable {
        @available(*, deprecated, renamed: "moduleName")
        public var targetName: String { self.moduleName }

        public let moduleName: String
        let packageIdentity: PackageIdentity
    }

    public var id: ID {
        ID(moduleName: self.name, packageIdentity: self.packageIdentity)
    }
}

@available(*, unavailable, message: "Use `Identifiable` conformance or `IdentifiableSet` instead")
extension ResolvedModule: Hashable {}
