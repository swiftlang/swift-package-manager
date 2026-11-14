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
    enum DependencyReference {
        case product(ResolvedProduct)
        case module(ResolvedModule)

        var packageIdentity: PackageIdentity {
            switch self {
            case .product(let product): product.packageIdentity
            case .module(let module): module.packageIdentity
            }
        }
    }

    internal func extractDependencies(product: String? = nil, target: String? = nil, filter: Filter = .all) async throws -> SBOMDependencies {
        guard let rootPackage = modulesGraph.rootPackages.first else {
            throw SBOMExtractorError.noRootPackage(context: "extract dependencies")
        }
        let primaryComponent = try await self.extractPrimaryComponent(product: product, target: target)
        let targetUnits: [DependencyReference]
        if let primaryReference = try self.extractPrimaryReference(product: product, target: target) {
            // only get dependencies for a single product or target
            targetUnits = [primaryReference]
        } else {
            // get dependencies for all products and public targets in the root package
            targetUnits = rootPackage.products.map { .product($0) } +
                Self.extractPublicModules(from: rootPackage).map { .module($0) }
        }
        return try await self.extractDependenciesForUnits(targetUnits: targetUnits, primaryComponent: primaryComponent, filter: filter)
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

    private func extractDependenciesForUnits(targetUnits: [DependencyReference], primaryComponent: SBOMComponent, filter: Filter) async throws -> SBOMDependencies {
        guard let rootPackage = modulesGraph.rootPackages.first else {
            throw SBOMExtractorError
                .noRootPackage(context: "extract dependencies for the following products and targets: \(targetUnits)")
        }

        let filterStrategy = filter.createStrategy()
        
        // Create the appropriate dependency source strategy
        let dependencySource: DependencySourceStrategy
        if let buildGraph = dependencyGraph {
            await self.populateTargetNameCache()
            dependencySource = BuildGraphDependencySource(
                dependencyGraph: buildGraph,
                modulesGraph: modulesGraph,
                caches: caches
            )
        } else {
            dependencySource = ModulesGraphDependencySource(modulesGraph: modulesGraph)
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

        func isPublicTarget(_ module: ResolvedModule, dependedOnBy unit: DependencyReference) -> Bool {
            module.packageIdentity != unit.packageIdentity && module.underlying.visibility == .public
        }

        // Processes modules recursively and returns a list of units to process.
        func processModuleDependency(
            from unit: DependencyReference,
            dependentModule: ResolvedModule
        ) async throws -> [DependencyReference] {
            var result: [DependencyReference] = []
            var modulesToProcess: [ResolvedModule] = [dependentModule]
            var processedModules = Set<ResolvedModule.ID>()

            while !modulesToProcess.isEmpty {
                let currentModule = modulesToProcess.removeFirst()
                guard processedModules.insert(currentModule.id).inserted else {
                    continue
                }
                let dependencies = try await dependencySource.getDependencies(for: currentModule)
                for dependency in dependencies {
                    switch dependency {
                    case .module(let dependentModule) where !isPublicTarget(dependentModule, dependedOnBy: unit):
                        if !processedModules.contains(dependentModule.id) {
                            modulesToProcess.append(dependentModule)
                        }
                    case .product, .module:
                        result.append(try await processUnitDependency(from: unit, dependentUnit: dependency))
                    }
                }
            }
            
            return result
        }

        // Takes a target/product and a dependent, processes the relationships, and then returns the dependent.
        func processUnitDependency(
            from unit: DependencyReference,
            dependentUnit: DependencyReference
        ) async throws -> DependencyReference {
            // if this relationship was already seen, return early
            let processedUnitComponent = try await extractComponent(unit)
            let dependentUnitComponent = try await extractComponent(dependentUnit)
            
            if let unitRelationships = relationships[processedUnitComponent],
               unitRelationships.contains(dependentUnitComponent) {
                return dependentUnit
            }

            // check if both units are in the same root package
            let bothInRootPackage = unit.packageIdentity == rootPackage.identity &&
                dependentUnit.packageIdentity == rootPackage.identity

            // only track dependency if not both in root package
            // this is because circular dependencies can be created in the SBOM
            // because products in the same root package can share or be composed of the same targets
            if !bothInRootPackage {
                // add unit -> dependentUnit dependency
                trackRelationship(parent: processedUnitComponent, child: dependentUnitComponent)
            }
            if let dependentUnitPackage = modulesGraph.packages
                .first(where: { $0.identity == dependentUnit.packageIdentity }) {
                let dependentUnitPackageComponent = try await extractComponent(package: dependentUnitPackage)
                // add dependentUnitPackage -> dependentUnit dependency
                trackRelationship(parent: dependentUnitPackageComponent, child: dependentUnitComponent)
                if let unitPackage = modulesGraph.packages.first(where: { $0.identity == unit.packageIdentity }) {
                    let unitPackageComponent = try await extractComponent(package: unitPackage)
                    // add unitPackage -> dependentUnitPackage dependency if they're from different packages
                    if unit.packageIdentity != dependentUnit.packageIdentity {
                        trackRelationship(
                            parent: unitPackageComponent,
                            child: dependentUnitPackageComponent
                        )
                    }
                    // add rootPackage -> unitPackage dependency if it's not the root package itself
                    if unitPackageComponent.id != rootPackageID {
                        trackRelationship(parent: rootPackageComponent, child: unitPackageComponent)
                    }
                }
            }
            return dependentUnit
        }

        func processDependencies(for unit: DependencyReference) async throws -> [DependencyReference] {
            var result: [DependencyReference] = []
            
            let dependencies: [DependencyReference]
            switch unit {
            case .product(let product):
                dependencies = try await dependencySource.getDependencies(for: product)
            case .module(let module):
                dependencies = try await dependencySource.getDependencies(for: module)
            }
            
            for dependency in dependencies {
                switch dependency {
                case .module(let dependentModule) where !isPublicTarget(dependentModule, dependedOnBy: unit):
                    result += try await processModuleDependency(
                        from: unit,
                        dependentModule: dependentModule
                    )
                case .product, .module:
                    result.append(try await processUnitDependency(
                        from: unit,
                        dependentUnit: dependency
                    ))
                }
            }
            return result
        }

        func processRelationships() -> [SBOMRelationship] {
            return relationships.map { parent, childrenSet in
                SBOMRelationship(
                    id: SBOMIdentifier(value: "\(parent.id.value)-depends-on"),
                    parentID: parent.id,
                    childrenID: Array(childrenSet.map { $0.id }).sorted { $0.value < $1.value }
                )
            }.sorted()
        }

        let rootPackageID = SBOMExtractor.extractComponentID(from: rootPackage)
        let rootPackageComponent = try await extractComponent(package: rootPackage)

        for targetUnit in targetUnits {
            let targetComponent = try await extractComponent(targetUnit)
            trackRelationship(parent: rootPackageComponent, child: targetComponent)
        }
        
        var processedUnits = Set<UnitID>()
        var unitsToProcess: [DependencyReference] = targetUnits

        while !unitsToProcess.isEmpty {
            let currentUnit = unitsToProcess.removeFirst()
            processedUnits.insert(UnitID(currentUnit))
            let transitiveDeps = try await processDependencies(for: currentUnit)
            for dep in transitiveDeps
                where !processedUnits.contains(UnitID(dep)) && !unitsToProcess.contains(where: { UnitID($0) == UnitID(dep) })
            {
                unitsToProcess.append(dep)
            }
        }

        return SBOMDependencies(
            components: Array(components).sorted(),
            relationships: processRelationships()
        )
    }
}

/// Identifies a product or target being processed by the dependency extractor.
private enum UnitID: Hashable {
    case product(ResolvedProduct.ID)
    case module(ResolvedModule.ID)

    init(_ reference: SBOMExtractor.DependencyReference) {
        switch reference {
        case .product(let product): self = .product(product.id)
        case .module(let module): self = .module(module.id)
        }
    }
}
