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
import Basics
import Foundation
import PackageModel
@testable import SBOMModel
import SourceControl
import Testing
import class TSCBasic.Process
import enum TSCUtility.Git

@Suite(
    .tags(
        .Feature.SBOM
    )
)
struct SBOMExtractPrimaryComponentTests {
    @Test("extractPrimaryComponent from sample SwiftPM ModulesGraph")
    func extractPrimaryComponentFromSPMModulesGraph() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractPrimaryComponent() }()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try spmRepo.getCurrentRevision().identifier

        #expect(component.category == .application)
        #expect(component.name == rootPackage.identity.description)
        #expect(component.id.value == rootPackage.identity.description)
        #expect(component.purl.description == "pkg:swift/github.com/swiftlang/swift-package-manager@\(expectedRevision)")
        #expect(component.version.revision == expectedRevision)
        #expect(component.version.commit?.sha == expectedRevision)
        #expect(component.version.commit?.repository == SBOMTestStore.swiftPMURL)
        #expect(component.scope == .runtime)
        #expect(component.description == rootPackage.description)

        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1)
        let firstCommit = try #require(commits.first)
        #expect(firstCommit.sha == expectedRevision)
        #expect(firstCommit.repository == SBOMTestStore.swiftPMURL)
    }

    @Test("extractPrimaryComponent from sample Swiftly ModulesGraph")
    func extractPrimaryComponentFromSwiftlyModulesGraph() async throws {
        let (swiftlyRepo, swiftlyPath) = try SBOMTestRepo.setupSwiftlyTestRepo()
        defer { try? SBOMTestRepo.cleanup(swiftlyPath) }

        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph(rootPath: swiftlyPath.pathString)
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractPrimaryComponent() }()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try swiftlyRepo.getCurrentRevision().identifier

        #expect(component.category == SBOMComponent.Category.application)
        #expect(component.name == rootPackage.identity.description)
        #expect(component.id.value == rootPackage.identity.description)
        #expect(component.purl.description == "pkg:swift/github.com/swiftlang/swiftly@v1.0.0")
        #expect(component.version.revision == "v1.0.0")
        #expect(component.version.commit?.sha == expectedRevision)
        #expect(component.version.commit?.repository == SBOMTestStore.swiftlyURL)
        #expect(component.scope == .runtime)
        #expect(component.description == rootPackage.description)
        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1)
        let firstCommit = try #require(commits.first)
        #expect(firstCommit.sha == expectedRevision)
        #expect(firstCommit.repository == SBOMTestStore.swiftlyURL)
    }

    @Test("extractComponent from product from primary component from sample SwiftPM ModulesGraph")
    func extractComponentFromProductFromSPMModulesGraph() async throws {
        let (gitRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let resolvedProduct = try #require(rootPackage.products.first { $0.name == "SwiftPMDataModel" })
        let actualRevision = try gitRepo.getCurrentRevision().identifier

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(product: resolvedProduct) }()

        #expect(component.category == SBOMComponent.Category.library)
        #expect(component.name == "SwiftPMDataModel")
        #expect(component.id.value == "swift-package-manager:SwiftPMDataModel")
        #expect(component.version.revision == actualRevision)
        #expect(component.scope == .runtime)
        #expect(component.purl.description
            .contains("pkg:swift/github.com/swiftlang/swift-package-manager:SwiftPMDataModel@\(actualRevision)"))
        #expect(component.description == nil)
        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1)
        let firstCommit = try #require(commits.first)
        #expect(firstCommit.sha == actualRevision)
        #expect(firstCommit.repository == SBOMTestStore.swiftPMURL)
    }

    @Test("extractComponent from product from primary component from sample Swiftly ModulesGraph")
    func extractComponentFromProductFromSwiftlyModulesGraph() async throws {
        let (swiftlyRepo, swiftlyPath) = try SBOMTestRepo.setupSwiftlyTestRepo()
        defer { try? SBOMTestRepo.cleanup(swiftlyPath) }

        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph(rootPath: swiftlyPath.pathString)
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let resolvedProduct = try #require(rootPackage.products.first)
        let actualRevision = try swiftlyRepo.getCurrentRevision().identifier

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(product: resolvedProduct) }()

        #expect(component.category == SBOMComponent.Category.application)
        #expect(component.name == "swiftly")
        #expect(component.id.value == "swiftly:swiftly")
        #expect(component.version.revision == "v1.0.0")
        #expect(component.scope == .runtime)
        #expect(component.purl.description.contains("pkg:swift/github.com/swiftlang/swiftly:swiftly@v1.0.0"))
        #expect(component.description == nil)

        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1)
        let firstCommit = try #require(commits.first)
        #expect(firstCommit.sha == actualRevision)
        #expect(firstCommit.repository == SBOMTestStore.swiftlyURL)
    }

    @Test("extractPrimaryComponent with product filter")
    func extractPrimaryComponentWithProductFilter() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()

        let productName = "SwiftPMDataModel"
        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractPrimaryComponent(product: productName) }()

        #expect(component.name == productName)
        #expect(component.id.value == "swift-package-manager:\(productName)")
        #expect(component.category == .library)

        let packageComponent = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractPrimaryComponent() }()
        #expect(packageComponent.name == "swift-package-manager")
        #expect(packageComponent.id.value == "swift-package-manager")
        #expect(component.category == .library)

        #expect(component.id != packageComponent.id)
    }

    @Test("SBOMVersionCache caches version information across multiple extractions")
    func versionCacheStoresAndReusesVersions() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try spmRepo.getCurrentRevision().identifier
        let caches = SBOMCaches()

        let component1 = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store,
            caches: caches
        ); return try await extractor.extractPrimaryComponent() }()
        #expect(component1.version.revision == expectedRevision)

        let cachedVersion = await caches.version.get(rootPackage.identity)
        #expect(cachedVersion != nil, "Cache should contain version for root package")
        #expect(cachedVersion?.version.revision == expectedRevision, "Cached version should match expected revision")

        let gitPath = spmPath.appending(".git")
        try localFileSystem.removeFileTree(gitPath)
        #expect(!localFileSystem.exists(gitPath), "Git directory should be removed")

        let component2 = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store,
            caches: caches
        ); return try await extractor.extractPrimaryComponent() }()
        #expect(component2.version.revision == expectedRevision, "Should return cached version even without Git")
        #expect(
            component2.version.revision == component1.version.revision,
            "Both extractions should return same version"
        )

        let resolvedProduct = try #require(rootPackage.products.first { $0.name == "SwiftPMDataModel" })
        let productComponent = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store,
            caches: caches
        ); return try await extractor.extractComponent(product: resolvedProduct) }()
        #expect(
            productComponent.version.revision == expectedRevision,
            "Product should use cached version from root package"
        )

        let cachedVersionAfter = await caches.version.get(rootPackage.identity)
        #expect(cachedVersionAfter?.version.revision == expectedRevision, "Cache should still contain same version")
    }

    @Test("extractComponent from package includes all products as nested components")
    func extractComponentFromPackageIncludesAllProducts() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        #expect(component.components != nil, "Package component should have nested product components")
        let nestedComponents = try #require(component.components)
        #expect(nestedComponents.count == rootPackage.products.count, "Should have one component per product")

        for product in rootPackage.products {
            let productComponent = nestedComponents.first { $0.name == product.name }
            #expect(productComponent != nil, "Should have component for product \(product.name)")
            #expect(productComponent?.id.value == "swift-package-manager:\(product.name)")
        }
    }

    @Test("extractComponent from package with executable product has application category")
    func extractComponentFromPackageWithExecutableHasApplicationCategory() async throws {
        let (_, swiftlyPath) = try SBOMTestRepo.setupSwiftlyTestRepo()
        defer { try? SBOMTestRepo.cleanup(swiftlyPath) }

        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph(rootPath: swiftlyPath.pathString)
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        #expect(component.category == .application, "Package with executable should be application category")
        #expect(component.name == "swiftly")
        #expect(component.id.value == "swiftly")
    }

    @Test("extractComponent from dependency package uses store version")
    func extractComponentFromDependencyPackageUsesStoreVersion() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()

        let dependencyPackage = try #require(graph.packages.first { $0.identity.description == "swift-system" })

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: dependencyPackage) }()

        #expect(component.name == "swift-system")
        #expect(component.id.value == "swift-system")
        #expect(component.category == .library)
        #expect(component.version.revision == "1.3.2")
        let expectedSHA = SBOMTestStore.generateMockRevision(for: "swift-system")
        #expect(component.version.commit?.sha == expectedSHA)
        #expect(component.version.commit?.repository == "https://github.com/apple/swift-system.git")
    }

    @Test("extractComponent from product without graph uses store version")
    func extractComponentFromProductWithoutGraphUsesStoreVersion() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()

        let dependencyPackage = try #require(graph.packages.first { $0.identity.description == "swift-collections" })
        let product = try #require(dependencyPackage.products.first { $0.name == "OrderedCollections" })

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(product: product) }()

        #expect(component.name == "OrderedCollections")
        #expect(component.id.value == "swift-collections:OrderedCollections")
        #expect(component.category == .library)
        #expect(component.version.revision == "1.1.4")
        #expect(component.description == nil, "Products should not have description")
    }

    @Test("extractComponent from package sets correct PURL")
    func extractComponentFromPackageSetsCorrectPURL() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        #expect(component.purl.description.hasPrefix("pkg:swift/github.com/swiftlang/swift-package-manager@"))
        #expect(component.purl.description.contains("github.com/swiftlang/swift-package-manager"))
    }

    @Test("extractComponent from product sets correct PURL with subpath")
    func extractComponentFromProductSetsCorrectPURLWithSubpath() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let product = try #require(rootPackage.products.first { $0.name == "SwiftPMPackageCollections" })

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(product: product) }()

        #expect(component.purl.description
            .contains("pkg:swift/github.com/swiftlang/swift-package-manager:SwiftPMPackageCollections@"))
        #expect(component.purl.description.contains(":SwiftPMPackageCollections@"))
    }

    @Test("extractComponent from package includes originator with commit info")
    func extractComponentFromPackageIncludesOriginatorWithCommitInfo() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try spmRepo.getCurrentRevision().identifier

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        #expect(component.originator.commits != nil)
        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1)
        #expect(commits.first?.sha == expectedRevision)
        #expect(commits.first?.repository == SBOMTestStore.swiftPMURL)
    }

    @Test("extractComponent from product includes originator with commit info")
    func extractComponentFromProductIncludesOriginatorWithCommitInfo() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let product = try #require(rootPackage.products.first)
        let expectedRevision = try spmRepo.getCurrentRevision().identifier

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(product: product) }()

        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1)
        let firstCommit = try #require(commits.first)
        #expect(firstCommit.sha == expectedRevision)
        #expect(firstCommit.repository == SBOMTestStore.swiftPMURL)
    }

    @Test("extractComponent from package preserves package description")
    func extractComponentFromPackagePreservesDescription() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        #expect(component.description == rootPackage.description)
    }

    @Test("extractComponent from product has nil description")
    func extractComponentFromProductHasNilDescription() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let product = try #require(rootPackage.products.first)

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(product: product) }()

        #expect(component.description == nil, "Products should not have description")
    }

    @Test("extractComponent from package extracts all products with correct properties")
    func extractComponentFromPackageExtractsAllProductsWithCorrectProperties() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try spmRepo.getCurrentRevision().identifier

        let packageComponent = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        let productComponents = try #require(packageComponent.components)
        #expect(productComponents.count == rootPackage.products.count)

        for (_, product) in rootPackage.products.enumerated() {
            let productComponent = try #require(productComponents.first { $0.name == product.name })
            #expect(productComponent.id.value == "swift-package-manager:\(product.name)")
            let expectedCategory: SBOMComponent.Category = product.type == .executable ? .application : .library
            #expect(productComponent.category == expectedCategory)
            #expect(productComponent.version.revision == expectedRevision)
            let versionCommit = try #require(productComponent.version.commit)
            #expect(versionCommit.sha == expectedRevision)
            #expect(productComponent.scope == .runtime || productComponent.scope == .test)
            #expect(productComponent.description == nil)
            #expect(productComponent.purl.description.contains(":\(product.name)@"))
        }
    }

    @Test("extractComponent from package with multiple product types extracts all correctly")
    func extractComponentFromPackageWithMultipleProductTypesExtractsAllCorrectly() async throws {
        let (_, swiftlyPath) = try SBOMTestRepo.setupSwiftlyTestRepo()
        defer { try? SBOMTestRepo.cleanup(swiftlyPath) }

        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph(rootPath: swiftlyPath.pathString)
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)

        let packageComponent = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        let productComponents = try #require(packageComponent.components)
        #expect(productComponents.count == rootPackage.products.count)

        let executableProduct = try #require(rootPackage.products.first { $0.type == .executable })
        let executableComponent = try #require(productComponents.first { $0.name == executableProduct.name })
        #expect(executableComponent.category == .application)
        #expect(executableComponent.id.value == "swiftly:swiftly")
    }

    @Test("extractComponent from dependency package extracts products with store versions")
    func extractComponentFromDependencyPackageExtractsProductsWithStoreVersions() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()

        let dependencyPackage = try #require(graph.packages.first { $0.identity.description == "swift-collections" })

        let packageComponent = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: dependencyPackage) }()

        let productComponents = try #require(packageComponent.components)
        #expect(productComponents.count == dependencyPackage.products.count)

        let expectedVersion = "1.1.4"
        let expectedSHA = SBOMTestStore.generateMockRevision(for: "swift-collections")
        for productComponent in productComponents {
            #expect(productComponent.version.revision == expectedVersion)
            #expect(productComponent.version.commit?.sha == expectedSHA)
        }

        let orderedCollections = try #require(productComponents.first { $0.name == "OrderedCollections" })
        #expect(orderedCollections.id.value == "swift-collections:OrderedCollections")
        #expect(orderedCollections.category == .library)
    }

    @Test("extractComponent from package with no products has empty components array")
    func extractComponentFromPackageWithNoProductsHasEmptyComponentsArray() async throws {
        // Create a simple package with no products for testing
        let packageIdentity = PackageIdentity.plain("TestPackage")
        let module = SBOMTestModulesGraph.createSwiftModule(name: "TestModule")
        let package = SBOMTestModulesGraph.createPackage(
            identity: packageIdentity,
            displayName: "TestPackage",
            path: "/TestPackage",
            modules: [module],
            products: []
        )
        let resolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: packageIdentity,
            module: module
        )
        let resolvedPackage = SBOMTestModulesGraph.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedModule]),
            products: []
        )

        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: resolvedPackage) }()

        #expect(component.components != nil)
        #expect(component.components?.isEmpty == true, "Package with no products should have empty components array")
    }

    @Test("extractComponent from package preserves product order")
    func extractComponentFromPackagePreservesProductOrder() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)

        let packageComponent = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        let productComponents = try #require(packageComponent.components)
        let productNames = productComponents.map(\.name)
        let expectedProductNames = rootPackage.products.map(\.name)

        #expect(
            productNames == expectedProductNames,
            "Product components should maintain the same order as package products"
        )
    }

    @Test("extractComponent uses origin remote for version commit")
    func extractComponentUsesOriginRemoteForVersionCommit() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        // Add a second remote to verify origin is preferred
        try await Process.checkNonZeroExit(
            args: Git.tool,
            "-C",
            spmPath.pathString,
            "remote",
            "add",
            "upstream",
            "https://github.com/apple/swift-package-manager.git"
        )

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try spmRepo.getCurrentRevision().identifier

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()

        // Verify the version commit uses the origin remote, not upstream
        let versionCommit = try #require(component.version.commit)
        #expect(versionCommit.repository == SBOMTestStore.swiftPMURL)
        #expect(versionCommit.sha == expectedRevision)

        // Verify originator still contains all remotes
        let commits = try #require(component.originator.commits)
        #expect(commits.count == 1, "Should prioritize origin remote")

        let originCommit = commits.first { $0.repository == SBOMTestStore.swiftPMURL }
        #expect(originCommit != nil, "Should have commit for origin remote")
    }

    @Test("extractComponent handles repository with no remotes")
    func extractComponentHandlesRepositoryWithNoRemotes() async throws {
        let uniqueID = UUID().uuidString
        let path = AbsolutePath("/tmp/SwiftPM-no-remotes-\(uniqueID)")
        defer { try? SBOMTestRepo.cleanup(path) }

        try localFileSystem.createDirectory(path, recursive: true)
        initGitRepo(path, addFile: true)

        // Don't add any remotes
        let gitRepo = GitRepository(path: path)
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: path.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let rootPackage = try #require(graph.rootPackages.first)
        let expectedRevision = try gitRepo.getCurrentRevision().identifier

        let component = try await { let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        ); return try await extractor.extractComponent(package: rootPackage) }()
        #expect(component.version.commit == nil)
        #expect(component.version.revision == expectedRevision)
        #expect(component.originator.commits == nil)
    }

    @Test("extractComponentID from package returns package identity")
    func extractComponentIDFromPackageReturnsPackageIdentity() throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let rootPackage = try #require(graph.rootPackages.first)

        let componentID = SBOMExtractor.extractComponentID(from: rootPackage)

        #expect(componentID.value == "MyApp")
        #expect(componentID.value == rootPackage.identity.description)
    }

    @Test("extractComponentID from product returns package:product format")
    func extractComponentIDFromProductReturnsPackageProductFormat() throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let rootPackage = try #require(graph.rootPackages.first)
        let product = try #require(rootPackage.products.first)

        let componentID = SBOMExtractor.extractComponentID(from: product)

        #expect(componentID.value == "MyApp:App")
        #expect(componentID.value.hasPrefix("\(product.packageIdentity):"))
        #expect(componentID.value.hasSuffix(":\(product.name)"))
    }

    @Test("extractComponentID from multiple products maintains correct format")
    func extractComponentIDFromMultipleProductsMaintainsCorrectFormat() throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let rootPackage = try #require(graph.rootPackages.first)
        for product in rootPackage.products {
            let componentID = SBOMExtractor.extractComponentID(from: product)
            let expectedID = "\(product.packageIdentity):\(product.name)"

            #expect(componentID.value == expectedID)
            #expect(componentID.value.contains(":"), "Product ID should contain colon separator")

            let parts = componentID.value.split(separator: ":")
            #expect(parts.count == 2, "Product ID should have exactly two parts")
            #expect(String(parts[0]) == product.packageIdentity.description)
            #expect(String(parts[1]) == product.name)
        }
    }

    @Test("extractComponentID from dependency packages returns correct identity")
    func extractComponentIDFromDependencyPackagesReturnsCorrectIdentity() throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        for package in graph.packages where package.identity.description != "swift-package-manager" {
            let componentID = SBOMExtractor.extractComponentID(from: package)

            #expect(componentID.value == package.identity.description)
            #expect(!componentID.value.contains(":"), "Package ID should not contain colon")
        }
    }
}
