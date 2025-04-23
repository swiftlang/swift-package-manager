//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

extension Package {
    /// The list of targets matching the given names. Throws an error if any of
    /// the targets cannot be found.
    public func targets(named targetNames: [String]) throws -> [Target] {
        return try targetNames.map { name in
            guard let target = self.targets.first(where: { $0.name == name }) else {
                throw PluginContextError.targetNotFound(name: name, package: self)
            }
            return target
        }
    }

    /// The list of products matching the given names. Throws an error if any of
    /// the products cannot be found.
    public func products(named productNames: [String]) throws -> [Product] {
        return try productNames.map { name in
            guard let product = self.products.first(where: { $0.name == name }) else {
                throw PluginContextError.productNotFound(name: name, package: self)
            }
            return product
        }
    }

    @available(_PackageDescription, introduced: 5.9)
    public var sourceModules: [SourceModuleTarget] {
        return targets.compactMap { $0.sourceModule }
    }
}

extension Product {
    @available(_PackageDescription, introduced: 5.9)
    public var sourceModules: [SourceModuleTarget] {
        return targets.compactMap { $0.sourceModule }
    }
}

extension Target {
    /// The transitive closure of all the targets on which the receiver depends,
    /// ordered such that every dependency appears before any other target that
    /// depends on it (i.e. in "topological sort order").
    public var recursiveTargetDependencies: [Target] {
        // FIXME: We can rewrite this to use a stack instead of recursion.
        var visited = Set<Target.ID>()
        func dependencyClosure(for target: Target) -> [Target] {
            guard visited.insert(target.id).inserted else { return [] }
            return target.dependencies.flatMap{ dependencyClosure(for: $0) } + [target]
        }
        func dependencyClosure(for dependency: TargetDependency) -> [Target] {
            switch dependency {
            case .target(let target):
                return dependencyClosure(for: target)
            case .product(let product):
                return product.targets.flatMap{ dependencyClosure(for: $0) }
            }
        }
        return self.dependencies.flatMap{ dependencyClosure(for: $0) }
    }

    /// Convenience accessor which casts the receiver to`SourceModuleTarget` if possible.
    @available(_PackageDescription, introduced: 5.9)
    public var sourceModule: SourceModuleTarget? {
        return self as? SourceModuleTarget
    }
}

extension Package {
    /// The products in this package that conform to a specific type.
    public func products<T: Product>(ofType: T.Type) -> [T] {
        return self.products.compactMap { $0 as? T }
    }

    /// The targets in this package that conform to a specific type.
    public func targets<T: Target>(ofType: T.Type) -> [T] {
        return self.targets.compactMap { $0 as? T }
    }
}

extension SourceModuleTarget {
    /// A possibly empty list of source files in the target that have the given
    /// filename suffix.
    public func sourceFiles(withSuffix suffix: String) -> FileList {
        return FileList(self.sourceFiles.filter{ $0.url.lastPathComponent.hasSuffix(suffix) })
    }
}
