//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageGraph
import PackageModel
import SwiftBuildSupport

/// Protocol defining the strategy for extracting dependencies from different sources
protocol DependencySourceStrategy {
    /// Get dependencies for a module
    func getDependencies(for module: ResolvedModule) async throws -> [SBOMExtractor.DependencyReference]
    
    /// Get dependencies for a product
    func getDependencies(for product: ResolvedProduct) async throws -> [SBOMExtractor.DependencyReference]
}

/// Strategy for extracting dependencies from the build graph
final class BuildGraphDependencySource: DependencySourceStrategy {
    private let dependencyGraph: [String: [String]]
    private let modulesGraph: ModulesGraph
    private let caches: SBOMCaches
    
    init(dependencyGraph: [String: [String]], modulesGraph: ModulesGraph, caches: SBOMCaches) {
        self.dependencyGraph = dependencyGraph
        self.modulesGraph = modulesGraph
        self.caches = caches
    }
    
    func getDependencies(for module: ResolvedModule) async throws -> [SBOMExtractor.DependencyReference] {
        guard let targetName = await caches.targetName.get(module.id),
              let targetDeps = dependencyGraph[targetName] else {
            return []
        }
        
        return targetDeps.compactMap { targetDep in
            if let product = SBOMGraphsConverter.toProduct(fromTarget: targetDep, modulesGraph: modulesGraph) {
                return .product(product)
            } else if let module = SBOMGraphsConverter.toModule(fromTarget: targetDep, modulesGraph: modulesGraph) {
                return .module(module)
            }
            // TODO: echeng3805, print a warning for targets not in modules graph (ignoring resource bundles)
            return nil
        }
    }
    
    func getDependencies(for product: ResolvedProduct) async throws -> [SBOMExtractor.DependencyReference] {
        guard let targetDeps = dependencyGraph[SBOMGraphsConverter.getTargetName(fromProduct: product.name)] else {
            return []
        }
        
        return targetDeps.compactMap { targetDep in
            if let product = SBOMGraphsConverter.toProduct(fromTarget: targetDep, modulesGraph: modulesGraph) {
                return .product(product)
            } else if let module = SBOMGraphsConverter.toModule(fromTarget: targetDep, modulesGraph: modulesGraph) {
                return .module(module)
            }
            // TODO: echeng3805, print a warning for targets not in modules graph?
            return nil
        }
    }
}

/// Strategy for extracting dependencies from the modules graph
final class ModulesGraphDependencySource: DependencySourceStrategy {
    private let modulesGraph: ModulesGraph
    
    init(modulesGraph: ModulesGraph) {
        self.modulesGraph = modulesGraph
    }
    
    func getDependencies(for module: ResolvedModule) async throws -> [SBOMExtractor.DependencyReference] {
        return module.dependencies.map { dependency in
            switch dependency {
            case .product(let product, _):
                return .product(product)
            case .module(let module, _):
                return .module(module)
            }
        }
    }
    
    func getDependencies(for product: ResolvedProduct) async throws -> [SBOMExtractor.DependencyReference] {
        return product.modules.flatMap { module in
            module.dependencies.map { dependency in
                switch dependency {
                case .product(let product, _):
                    return .product(product)
                case .module(let module, _):
                    return .module(module)
                }
            }
        }
    }
}