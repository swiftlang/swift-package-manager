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

import _InternalTestSupport
import Foundation
import PackageGraph
@testable import SBOMModel
import Testing

struct SBOMExtractDependenciesTests {

    // MARK: - Helper Methods for Validation


    private func detectCycles(in dependencies: [SBOMRelationship]) -> [String] {
        var graph: [String: [String]] = [:]
        for dependency in dependencies {
            graph[dependency.parentID.value] = dependency.childrenID.map(\.value)
        }

        var visited: Set<String> = []
        var recursionStack: Set<String> = []
        var cycles: [String] = []

        func dfs(node: String, path: [String]) {
            if recursionStack.contains(node) {
                // Found a cycle - build the cycle path
                if let cycleStart = path.firstIndex(of: node) {
                    let cyclePath = (path[cycleStart...] + [node]).joined(separator: " -> ")
                    cycles.append(cyclePath)
                }
                return
            }
            if visited.contains(node) {
                return
            }
            visited.insert(node)
            recursionStack.insert(node)
            if let children = graph[node] {
                for child in children {
                    dfs(node: child, path: path + [node])
                }
            }
            recursionStack.remove(node)
        }
        for node in graph.keys {
            if !visited.contains(node) {
                dfs(node: node, path: [])
            }
        }
        return cycles
    }
    
    private func isProductID(_ id: String) -> Bool {
        id.contains(":")
    }
    
    private func isOwnProduct(childID: String, parentID: String) -> Bool {
        childID.hasPrefix(parentID)
    }
    
    private func validateOwnProductDependency(childID: String, parentID: String) {
        #expect(
            isOwnProduct(childID: childID, parentID: parentID),
            "Package '\(parentID)' product dependency '\(childID)' should depend on '\(parentID)'"
        )
    }
    
    private func validatePackageDependency(childID: String, parentID: String, packageIDs: [String]) {
        #expect(
            packageIDs.contains(childID),
            "Package '\(parentID)' package dependency '\(childID)' should be a valid package"
        )
    }
    
    private func validateProductDependency(childID: String, parentID: String) {
        #expect(
            isProductID(childID),
            "Product '\(parentID)' should only depend on other products, but found package dependency '\(childID)'"
        )
    }
    
    private func validatePackageChildren(
        dependency: SBOMRelationship,
        rootPackageID: String,
        packageIDs: [String],
        filter: Filter = .all
    ) {
        for child in dependency.childrenID {
            if isProductID(child.value) { // package-to-product
                // root-package to root product is allowed when filter == .package or .product
                if filter == .package && rootPackageID != dependency.parentID.value {
                    #expect(!isProductID(child.value), "Package \(dependency.parentID) should only depend on packages when filter is .package'")
                    return
                } else if filter == .product && rootPackageID != dependency.parentID.value { 
                    #expect(!isProductID(child.value), "Package \(dependency.parentID) should only depend on root products and not other products when filter is .product'")
                    return
                }
                validateOwnProductDependency(childID: child.value, parentID: dependency.parentID.value)
            } else { // package-to-package
                validatePackageDependency(childID: child.value, parentID: dependency.parentID.value, packageIDs: packageIDs)
            }
        }
    }
    
    private func validateProductChildren(dependency: SBOMRelationship) {
        for child in dependency.childrenID { // product-to-product
            validateProductDependency(childID: child.value, parentID: dependency.parentID.value)
        }
    }
    
    private func validateRootPackageChildren(
        dependency: SBOMRelationship,
        rootPackageID: String,
        packageIDs: [String],
        filter: Filter = .all
    ) {
        #expect(!dependency.childrenID.map(\.value).contains(rootPackageID))
        validatePackageChildren(dependency: dependency, rootPackageID: rootPackageID, packageIDs: packageIDs, filter: filter)
    }
    
    private func verifyProductDependencies(
        graph: ModulesGraph,
        store: ResolvedPackagesStore,
        dependencyGraph: [String: [String]]? = nil,
        filter: Filter = .all,
        product: String? = nil,
    ) async throws {
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: dependencyGraph, store: store)
        let dependencies = try await #require(extractor.extractDependencies(product: product, filter: filter).relationships)
        let rootPackage = try #require(graph.rootPackages.first)
        let rootPackageID = SBOMExtractor.extractComponentID(from: rootPackage).value
        let packageIDs = graph.packages.map(\.identity.description)

        #expect(!dependencies.isEmpty)

        let parentIDs = dependencies.map(\.parentID)
        #expect(parentIDs.count == Set(parentIDs).count, "Parent IDs should be unique")

        let cycles = self.detectCycles(in: dependencies)
        #expect(cycles.isEmpty, "Dependency graph should not contain cycles. Found: \(cycles.joined(separator: "; "))")

        for dependency in dependencies {
            #expect(!dependency.id.value.isEmpty, "Dependency ID should not be empty")
            #expect(!dependency.parentID.value.isEmpty, "Parent ID should not be empty")
            #expect(!dependency.childrenID.isEmpty, "Children ID should not be empty")

            #expect(
                !dependency.childrenID.map(\.value).contains(dependency.parentID.value),
                "parent '\(dependency.parentID.value)' should not depend on itself"
            )

            if packageIDs.contains(dependency.parentID.value) { // package-to-product or package-to-package
                validatePackageChildren(dependency: dependency, rootPackageID: rootPackageID, packageIDs: packageIDs, filter: filter)
            } else {
                // product-to-product
                validateProductChildren(dependency: dependency)
            }

            if product == nil {
                #expect(!dependency.childrenID.map(\.value).contains(rootPackageID))
            }
        }
    }

    @Test("extractDependencies with sample SPM ModulesGraph")
    func extractDependenciesFromSPMModulesGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        try await self.verifyProductDependencies(graph: graph, store: store)
    }

    @Test("extractDependencies with sample Swiftly ModulesGraph")
    func extractDependenciesFromSwiftlyModulesGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        try await self.verifyProductDependencies(graph: graph, store: store)
    }

    @Test("extractDependencies with product filter SwiftPMPackageCollections")
    func extractDependenciesWithProductFilter() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()

        let productName = "SwiftPMPackageCollections"
        try await self.verifyProductDependencies(graph: graph, store: store, product: productName)
    }

    @Test("extractDependencies with product filter SwiftPMDataModel")
    func extractDependenciesWithProductFilterSwiftPMDataModel() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()

        let productName = "SwiftPMDataModel"
        try await self.verifyProductDependencies(graph: graph, store: store, product: productName)
    }

    @Test("extractDependencies with simple test graph")
    func extractDependenciesFromSimpleGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        try await self.verifyProductDependencies(graph: graph, store: store)
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let dependencies = try await #require(extractor.extractDependencies().relationships)

        #expect(dependencies.count == 3, "Simple graph should have exactly 3 dependency relationships")

        let myAppPackageDep = try #require(dependencies.first { $0.parentID.value == "MyApp" })
        let utilsPackageDep = try #require(dependencies.first { $0.parentID.value == "Utils" })
        let appProductDep = try #require(dependencies.first { $0.parentID.value == "MyApp:App" })

        #expect(myAppPackageDep.childrenID.count == 2, "MyApp package should have 2 dependencies")
        #expect(myAppPackageDep.childrenID.map(\.value).contains("Utils"), "MyApp should depend on Utils package")
        #expect(
            myAppPackageDep.childrenID.map(\.value).contains("MyApp:App"),
            "MyApp should depend on its own App product"
        )

        #expect(utilsPackageDep.childrenID.count == 1, "Utils package should have 1 dependency")
        #expect(
            utilsPackageDep.childrenID.map(\.value).contains("Utils:Utils"),
            "Utils should depend on its own Utils product"
        )

        #expect(appProductDep.childrenID.count == 1, "App product should have 1 dependency")
        #expect(
            appProductDep.childrenID.map(\.value).contains("Utils:Utils"),
            "App product should depend on Utils product"
        )
    }

    // MARK: - Build Graph Tests

    @Test("extractDependencies with build graph for simple test graph")
    func extractDependenciesFromSimpleGraphWithBuildGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let buildGraph = SBOMTestDependencyGraph.createSimpleDependencyGraph()

        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: buildGraph, store: store)
        let dependencies = try await #require(extractor.extractDependencies().relationships)

        #expect(!dependencies.isEmpty, "Should have dependencies when using build graph")

        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph)

        let myAppPackageDep = try #require(dependencies.first { $0.parentID.value == "MyApp" })
        let utilsPackageDep = try #require(dependencies.first { $0.parentID.value == "Utils" })
        let appProductDep = try #require(dependencies.first { $0.parentID.value == "MyApp:App" })

        #expect(myAppPackageDep.childrenID.count == 2, "MyApp package should have 2 dependencies")
        #expect(myAppPackageDep.childrenID.map(\.value).contains("Utils"), "MyApp should depend on Utils package")
        #expect(
            myAppPackageDep.childrenID.map(\.value).contains("MyApp:App"),
            "MyApp should depend on its own App product"
        )

        #expect(utilsPackageDep.childrenID.count == 1, "Utils package should have 1 dependency")
        #expect(
            utilsPackageDep.childrenID.map(\.value).contains("Utils:Utils"),
            "Utils should depend on its own Utils product"
        )

        #expect(appProductDep.childrenID.count == 1, "App product should have 1 dependency")
        #expect(
            appProductDep.childrenID.map(\.value).contains("Utils:Utils"),
            "App product should depend on Utils product"
        )
    }

    @Test("extractDependencies with build graph for SPM ModulesGraph")
    func extractDependenciesFromSPMModulesGraphWithBuildGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let buildGraph = SBOMTestDependencyGraph.createSPMDependencyGraph()
        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph)
    }

    @Test("extractDependencies with build graph for Swiftly ModulesGraph")
    func extractDependenciesFromSwiftlyModulesGraphWithBuildGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let buildGraph = SBOMTestDependencyGraph.createSwiftlyDependencyGraph()
        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph)
    }

    @Test("extractDependencies with build graph and product filter for SPM")
    func extractDependenciesWithBuildGraphAndProductFilterSPM() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let buildGraph = SBOMTestDependencyGraph.createSPMDependencyGraph()
        let productName = "SwiftPMPackageCollections"
        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph, product: productName)
    }

    @Test("extractDependencies with build graph and product filter for Swiftly")
    func extractDependenciesWithBuildGraphAndProductFilterSwiftly() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let buildGraph = SBOMTestDependencyGraph.createSwiftlyDependencyGraph()
        let productName = "swiftly"
        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph, product: productName)
    }

    @Test("extractDependencies with empty build graph falls back to ModulesGraph")
    func extractDependenciesWithEmptyBuildGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        // Empty build graph - should fall back to ModulesGraph
        let buildGraph: [String: [String]] = [:]
        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph)
    }

    @Test("extractDependencies with simple different build graph doesn't have some dependencies")
    func extractDependenciesWithSimpleDifferenntBuildGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let buildGraph = SBOMTestDependencyGraph.createSimpleDifferentDependencyGraph()
        try await self.verifyProductDependencies(graph: graph, store: store, dependencyGraph: buildGraph)
    
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: buildGraph, store: store)
        let dependencies = try await #require(extractor.extractDependencies().relationships)

        #expect(!dependencies.isEmpty, "Should have dependencies when using build graph")

        let myAppPackageDep = try #require(dependencies.first { $0.parentID.value == "MyApp" })
        #expect(myAppPackageDep.childrenID.count == 1, "MyApp package should have 1 dependency")
        #expect(myAppPackageDep.childrenID.map(\.value).contains("MyApp:App"), "MyApp should depend on App product")

        let appProductDep = dependencies.first { $0.parentID.value == "MyApp:App" }
        #expect(appProductDep == nil, "App product should not appear in dependencies as parent")
        let utilsPackageDep = dependencies.first { $0.parentID.value == "Utils" }
        #expect(utilsPackageDep == nil, "Utils package should not appear in dependencies as parent")
        let utilsProductDep = dependencies.first { $0.parentID.value == "Utils:Util" }
        #expect(utilsProductDep == nil, "Util product should not appear in dependencies as parent")
    }
    
    // MARK: - Filter Tests
    
    @Test("Filter.all tracks all relationships")
    func filterAllTracksAllRelationships() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        try await self.verifyProductDependencies(graph: graph, store: store)
    }
    
    @Test("Filter.product tracks only product-to-product and cross-boundary relationships when primary component is package")
    func filterProductTracksOnlyProductRelationships() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()        
        try await self.verifyProductDependencies(graph: graph, store: store, filter: .product, product: nil)
    }
    
    @Test("Filter.package tracks only package-to-package relationships when primary component is package")
    func filterPackageTracksOnlyPackageRelationships() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()        
        try await self.verifyProductDependencies(graph: graph, store: store, filter: .package, product: nil)
    }

    @Test("Filter.product tracks only product-to-product when primary component is product")
    func filterProductTracksOnlyProductRelationshipsForProduct() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        try await self.verifyProductDependencies(graph: graph, store: store, filter: .product, product: "SwiftPMDataModel")
    }
    
    @Test("Filter.package tracks only package-to-package relationships and cross-boundary relationships when primary component is product")
    func filterPackageTracksOnlyPackageRelationshipsForProduct() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        try await self.verifyProductDependencies(graph: graph, store: store, filter: .package, product: "SwiftPMDataModel")
    }
}
