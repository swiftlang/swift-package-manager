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

import Basics
import Foundation
import PackageCollections
import PackageGraph
import PackageModel
import SourceControl
import TSCUtility

extension SBOMExtractor {
    enum DependencySource {
        case buildGraph
        case modulesGraph
    }

    enum DependencyReference {
        case product(ResolvedProduct)
        case module(ResolvedModule)
    }

    internal func extractDependencies(product: String? = nil, filter: Filter = .all) async throws -> SBOMDependencies {
        guard let rootPackage = modulesGraph.rootPackages.first else {
            throw SBOMExtractorError.noRootPackage(context: "extract dependencies")
        }
        let primaryComponent = try await self.extractPrimaryComponent(product: product)
        let targetProducts: [ResolvedProduct]
        if let name = product {
            guard let targetProduct = rootPackage.products.first(where: { $0.name == name }) else {
                throw SBOMExtractorError.productNotFound(
                    productName: name,
                    packageIdentity: rootPackage.identity.description
                )
            }
            // only get dependencies for single product
            targetProducts = [targetProduct]
        } else {
            // get dependencies for all products in the root package
            targetProducts = rootPackage.products
        }
        return try await self.extractDependenciesForProducts(targetProducts: targetProducts, primaryComponent: primaryComponent, filter: filter)
    }

    private func populateTargetNameCache() async {
        if let buildGraph = dependencyGraph {
            for targetName in buildGraph.keys {
                if let module = SBOMGraphsConverter.toModule(fromTarget: targetName, modulesGraph: modulesGraph) {
                    await caches.targetName.set(module.id, targetName: targetName)
                }
            }
        }
    }

    private func extractDependenciesForProducts(targetProducts: [ResolvedProduct], primaryComponent: SBOMComponent, filter: Filter) async throws -> SBOMDependencies {
        guard let rootPackage = modulesGraph.rootPackages.first else {
            throw SBOMExtractorError
                .noRootPackage(context: "extract dependencies for the following products: \(targetProducts)")
        }

        let filterStrategy = filter.createStrategy()
        let source = dependencyGraph != nil ? DependencySource.buildGraph : DependencySource.modulesGraph
        if source == .buildGraph {
            await self.populateTargetNameCache()
        }
        
        var components: Set<SBOMComponent> = []
        var relationships: [SBOMComponent: Set<SBOMComponent>] = [:] // parent:children
        
        func addComponent(_ component: SBOMComponent) {
            if filterStrategy.shouldIncludeComponent(component, primaryComponent: primaryComponent) {
                components.insert(component)
            }
        }

        func trackRelationship(parent: SBOMComponent, child: SBOMComponent) {
            if filterStrategy.shouldTrackRelationship(parent: parent, child: child, primaryComponent: primaryComponent) {
                addComponent(parent)
                addComponent(child)
                relationships[parent, default: []].insert(child)
            }
        }

        // Get dependencies for a module based on the source
        func getDependencies(forModule module: ResolvedModule) async throws -> [DependencyReference] {
            switch source {
            case .buildGraph:
                return try await getBuildGraphDependencies(forModule: module)
            case .modulesGraph:
                return getModulesGraphDependencies(forModule: module)
            }
        }

        // Get dependencies for a product based on the source
        func getDependencies(forProduct product: ResolvedProduct) async throws -> [DependencyReference] {
            switch source {
            case .buildGraph:
                return try await getBuildGraphDependencies(forProduct: product)
            case .modulesGraph:
                return getModulesGraphDependencies(forProduct: product)
            }
        }

        // Get dependencies for a module from build graph
        func getBuildGraphDependencies(forModule module: ResolvedModule) async throws -> [DependencyReference] {
            guard let buildGraph = dependencyGraph,
                  let targetName = await caches.targetName.get(module.id),
                  let targetDeps = buildGraph[targetName] else {
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

        // Get dependencies for a module from modules graph
        func getModulesGraphDependencies(forModule module: ResolvedModule) -> [DependencyReference] {
            return module.dependencies.map { dependency in
                switch dependency {
                case .product(let product, _):
                    return .product(product)
                case .module(let module, _):
                    return .module(module)
                }
            }
        }

        // Get product dependencies from modules graph
        func getModulesGraphDependencies(forProduct product: ResolvedProduct) -> [DependencyReference] {
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

        // Get dependencies for a product from build graph
        func getBuildGraphDependencies(forProduct product: ResolvedProduct) async throws -> [DependencyReference] {
            guard let buildGraph = dependencyGraph,
                  let targetDeps = buildGraph[SBOMGraphsConverter.getTargetName(fromProduct: product.name)] else {
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

        // Processes modules recursively and returns a list of products to process.
        func processModuleDependency(
            from product: ResolvedProduct,
            dependentModule: ResolvedModule
        ) async throws -> [ResolvedProduct] {
            var result: [ResolvedProduct] = []
            var modulesToProcess: [ResolvedModule] = [dependentModule]
            var processedModules = Set<ResolvedModule.ID>()

            while !modulesToProcess.isEmpty {
                let currentModule = modulesToProcess.removeFirst()
                guard processedModules.insert(currentModule.id).inserted else {
                    continue
                }
                let dependencies = try await getDependencies(forModule: currentModule)
                for dependency in dependencies {
                    switch dependency {
                    case .product(let dependentProduct):
                        if let processed = try await processProductDependency(from: product, dependentProduct: dependentProduct) {
                            result.append(processed)
                        }
                    case .module(let dependentModule):
                        if !processedModules.contains(dependentModule.id) {
                            modulesToProcess.append(dependentModule)
                        }
                    }
                }
            }
            
            return result
        }

        // Takes a product and a dependent product, processes the relationships, and then returns the dependent product.
        func processProductDependency(
            from product: ResolvedProduct,
            dependentProduct: ResolvedProduct
        ) async throws -> ResolvedProduct? {
            // if this relationship was already seen, return early
            let processedProductComponent = try await extractComponent(product: product)
            let dependentProductComponent = try await extractComponent(product: dependentProduct)
            
            if let productRelationships = relationships[processedProductComponent],
               productRelationships.contains(dependentProductComponent) {
                return dependentProduct
            }

            // check if both products are in the same root package
            let bothInRootPackage = product.packageIdentity == rootPackage.identity &&
                dependentProduct.packageIdentity == rootPackage.identity

            // only track dependency if not both in root package
            // this is because circular dependencies can be created in the SBOM
            // because products in the same root package can share or be composed of the same targets
            if !bothInRootPackage {
                // add product -> dependentProduct dependency
                trackRelationship(parent: processedProductComponent, child: dependentProductComponent)
            }
            if let dependentProductPackage = modulesGraph.packages
                .first(where: { $0.identity == dependentProduct.packageIdentity }) {
                let dependentProductPackageComponent = try await extractComponent(package: dependentProductPackage)
                // add dependentProductPackage -> dependentProduct dependency
                trackRelationship(parent: dependentProductPackageComponent, child: dependentProductComponent)
                if let productPackage = modulesGraph.packages.first(where: { $0.identity == product.packageIdentity }) {
                    let productPackageComponent = try await extractComponent(package: productPackage)
                    // add productPackage -> dependentProductPackage dependency if they're from different packages
                    if product.packageIdentity != dependentProduct.packageIdentity {
                        trackRelationship(
                            parent: productPackageComponent,
                            child: dependentProductPackageComponent
                        )
                    }
                    // add rootPackage -> productPackage dependency if it's not the root package itself
                    if productPackageComponent.id != rootPackageID {
                        trackRelationship(parent: rootPackageComponent, child: productPackageComponent)
                    }
                }
            }
            return dependentProduct
        }

        func processDependencies(for product: ResolvedProduct) async throws -> [ResolvedProduct] {
            var result = IdentifiableSet<ResolvedProduct>()
            
            let dependencies = try await getDependencies(forProduct: product)
            
            for dependency in dependencies {
                switch dependency {
                case .product(let dependentProduct):
                    if let toProcess = try await processProductDependency(
                        from: product,
                        dependentProduct: dependentProduct
                    ) {
                        result.insert(toProcess)
                    }
                case .module(let dependentModule):
                    let toProcess = try await processModuleDependency(
                        from: product,
                        dependentModule: dependentModule
                    )
                    for productToProcess in toProcess {
                        result.insert(productToProcess)
                    }
                }
            }
            return Array(result)
        }

        func processRelationships() -> [SBOMRelationship] {
            return relationships.map { parent, childrenSet in
                SBOMRelationship(
                    id: SBOMIdentifier(value: "\(parent.id.value)-depends-on"),
                    parentID: parent.id,
                    childrenID: Array(childrenSet.map { $0.id })
                )
            }
        }

        let rootPackageID = SBOMExtractor.extractComponentID(from: rootPackage)
        let rootPackageComponent = try await extractComponent(package: rootPackage)

        for targetProduct in targetProducts {
            let targetComponent = try await extractComponent(product: targetProduct)
            trackRelationship(parent: rootPackageComponent, child: targetComponent)
        }
        
        var processedProducts = IdentifiableSet<ResolvedProduct>()
        var productsToProcess: [ResolvedProduct] = targetProducts

        while !productsToProcess.isEmpty {
            let currentProduct = productsToProcess.removeFirst()
            processedProducts.insert(currentProduct)
            let transitiveDeps = try await processDependencies(for: currentProduct)
            for dep in transitiveDeps
                where !processedProducts.contains(id: dep.id) && !productsToProcess.contains(where: { $0.id == dep.id })
            {
                productsToProcess.append(dep)
            }
        }

        return SBOMDependencies(
            components: Array(components),
            relationships: processRelationships()
        )
    }
}
