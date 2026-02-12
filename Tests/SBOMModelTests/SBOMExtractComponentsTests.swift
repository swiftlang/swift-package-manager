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
import PackageGraph
import PackageModel
import PackageRegistry
@testable import SBOMModel
import Testing
import class TSCBasic.Process

import enum TSCUtility.Git
import struct TSCUtility.Version

@Suite(
    .tags(
        .Feature.SBOM
    )
)
struct SBOMExtractComponentsTests {
    struct TestExpectations {
        let totalComponentCount: Int
        let expectedPackageIds: Set<String>
        let rootPackage: String
        let rootPackagePrefix: String
        let expectedRootProductCount: Int
        let expectedRootProductNames: Set<String>
    }

    private static let simpleExpectations = TestExpectations(
        totalComponentCount: 4,
        expectedPackageIds: Set(["MyApp", "Utils"]),
        rootPackage: "MyApp",
        rootPackagePrefix: "MyApp:",
        expectedRootProductCount: 1,
        expectedRootProductNames: Set(["App"]),
    )
    private static let spmExpectations = TestExpectations(
        totalComponentCount: 57,
        expectedPackageIds: Set([
            "swift-build", "swift-llbuild", "swift-driver", "swift-certificates", "swift-syntax",
            "swift-tools-support-core",
            "swift-crypto", "swift-argument-parser", "swift-asn1", "swift-collections", "swift-system",
            "swift-package-manager",
            "swift-toolchain-sqlite",
        ]),
        rootPackage: "swift-package-manager",
        rootPackagePrefix: "swift-package-manager:",
        expectedRootProductCount: 24,
        expectedRootProductNames: Set([
            "swift-package-registry", "PackageDescription", "PackageCollectionsModel", "swift-test",
            "swift-package-collection",
            "swift-sdk", "SwiftPMPackageCollections", "swift-experimental-sdk", "swift-package", "swift-run",
            "PackagePlugin",
            "swift-build-prebuilts", "SwiftPMDataModel", "swift-build", "package-info", "dummy-swiftc",
            "SwiftPMDataModel-auto",
            "XCBuildSupport", "swift-package-manager", "SwiftPM-auto", "AppleProductTypes", "swift-bootstrap",
            "swiftpm-testing-helper",
            "SwiftPM",
        ]),
    )

    private static let swiftlyExpectations = TestExpectations(
        totalComponentCount: 64,
        expectedPackageIds: Set(["swift-nio-http2", "swift-tools-support-core",
                                 "swift-nio-transport-services", "swiftly",
                                 "swift-distributed-tracing", "swift-service-context", "swift-nio-ssl",
                                 "swift-nio", "swift-collections", "swift-system", "swift-algorithms",
                                 "swift-openapi-generator", "swift-openapi-async-http-client",
                                 "swift-argument-parser", "openapikit", "yams", "swift-subprocess",
                                 "async-http-client", "swift-log", "swift-atomics", "swift-numerics",
                                 "swift-openapi-runtime", "swift-http-types", "swift-nio-extras"]),
        rootPackage: "swiftly",
        rootPackagePrefix: "swiftly:",
        expectedRootProductCount: 6,
        expectedRootProductNames: Set([
            "test-swiftly",
            "swiftly",
            "generate-command-models",
            "SwiftlyTests",
            "build-swiftly-release",
            "generate-docs-reference",
        ]),
    )

    private func verifyComponents(
        components: [SBOMComponent],
        graph: ModulesGraph,
        expectations: TestExpectations,
        filter: Filter = .all,
        product: String? = nil
    ) {
        let isFullExtraction = filter == .all && product == nil
        verifyComponentCounts(components, expectations: expectations, isFullExtraction: isFullExtraction)
        verifyPackageIds(components, expectations: expectations, isFullExtraction: isFullExtraction)
        verifyRootProducts(components, expectations: expectations, filter: filter, product: product)
        verifyComponentProperties(components, filter: filter)
    }
    
    private func verifyComponentCounts(
        _ components: [SBOMComponent],
        expectations: TestExpectations,
        isFullExtraction: Bool
    ) {
        if isFullExtraction {
            #expect(components.count == expectations.totalComponentCount)
        } else {
            #expect(components.count <= expectations.totalComponentCount)
        }
    }
    
    private func verifyPackageIds(
        _ components: [SBOMComponent],
        expectations: TestExpectations,
        isFullExtraction: Bool
    ) {
        let componentPackageIds = Set(components.compactMap { component in
            component.id.value.components(separatedBy: ":").first
        })
        if isFullExtraction {
            #expect(componentPackageIds == expectations.expectedPackageIds, "Package IDs did not match")
        } else {
            #expect(componentPackageIds.isSubset(of: expectations.expectedPackageIds), "Package IDs should be a subset")
        }
    }

    private func verifyRootPackage(
        _ components: [SBOMComponent],
        expectations: TestExpectations,
        filter: Filter,
        product: String?
    ) {
        let rootPackageComponent = components.first { $0.id.value == expectations.rootPackage && $0.entity == .package }
        // If filter is product AND the primary component is a product, the root package should NOT be included
        if let productName = product {
            if filter == .product {
                #expect(rootPackageComponent == nil, "Root package should not be included when filter is .product and primary component '\(productName)' is a product")
                return
            }
        } // else it's always included
         #expect(rootPackageComponent != nil, "Root package should be included")
    }
    
    private func verifyRootProducts(
        _ components: [SBOMComponent],
        expectations: TestExpectations,
        filter: Filter,
        product: String?
    ) {
        let rootProducts = components.filter { $0.id.value.hasPrefix(expectations.rootPackagePrefix) }
        let rootProductComponents = rootProducts.filter { $0.entity == .product }

        if let productName = product {
            // if product is primary component, it should always show up in components, regardless of filter
            let targetProduct = rootProductComponents.first { $0.name == productName }
            #expect(targetProduct != nil, "Target product '\(productName)' should be included")
        } else {
            if filter == .all || filter == .product {
                // expect all root products if filter is .all or .product, and primary component is root package
                #expect(rootProducts.count == expectations.expectedRootProductCount, "Filter.\(filter) should include all root products")
                let rootProductNames = Set(rootProductComponents.map(\.name))
                #expect(rootProductNames == expectations.expectedRootProductNames, "Root product names should match expectations")
            } else if filter == .package {
                // no root products if filter is .package, and primary component is root package
                #expect(rootProducts.count == 0, "Filter.\(filter) should include no root products")
            }
        }
    }
    
    private func verifyComponentProperties(_ components: [SBOMComponent], filter: Filter) {
        for component in components {
            #expect(!component.id.value.isEmpty, "Component ID should not be empty")
            #expect(!component.name.isEmpty, "Component name should not be empty")
            #expect(!component.purl.description.isEmpty, "Component PURL should not be empty")
            #expect(!component.version.revision.isEmpty, "Component version should not be empty")
            #expect(
                component.category == .application || component.category == .library,
                "Component category should be application or library"
            )
            #expect(
                component.scope == .runtime || component.scope == .test,
                "Component scope should be runtime or test"
            )
        }
    }

    @Test("extractComponents with sample SPM ModulesGraph")
    func extractComponentsFromSPMModulesGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components
        self.verifyComponents(components: components, graph: graph, expectations: Self.spmExpectations)
    }

    @Test("extractComponents with sample Swiftly ModulesGraph")
    func extractComponentsFromSwiftlyModulesGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components
        self.verifyComponents(components: components, graph: graph, expectations: Self.swiftlyExpectations)
    }

    @Test("extractComponents fails with empty root packages")
    func extractComponentsFailsWithEmptyRootPackages() async throws {
        let emptyGraph = try ModulesGraph(
            rootPackages: [],
            rootDependencies: [],
            packages: IdentifiableSet([]),
            dependencies: [],
            binaryArtifacts: [:]
        )
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        await #expect(throws: SBOMExtractorError.self) {
            let extractor = SBOMExtractor(modulesGraph: emptyGraph, dependencyGraph: nil, store: store)
            _ = try await extractor.extractDependencies().components
        }
    }

    @Test("extractComponents verifies commit extraction for non-main branch dependency")
    func extractComponentsForNonMainBranch() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components

        let swiftLLBuildComponent = components.first { component in
            component.id.value == "swift-llbuild" || component.name == "swift-llbuild"
        }

        let component = try #require(swiftLLBuildComponent, "swift-llbuild component should be found")

        let commits = try #require(
            component.originator.commits,
            "swift-llbuild component should have commit information"
        )
        #expect(!commits.isEmpty, "swift-llbuild should have at least one commit")

        let commit = commits[0]
        #expect(!commit.sha.isEmpty, "Commit SHA should not be empty")
        #expect(commit.repository == "https://github.com/swiftlang/swift-llbuild.git", "Repository URL should match")

        let expectedMockRevision = SBOMTestStore.generateMockRevision(for: "swift-llbuild")
        #expect(commit.sha == expectedMockRevision, "Commit SHA should match the mock revision for swift-llbuild")

        #expect(
            component.version.revision == commit.sha,
            "Component version should match commit SHA for branch-based dependency"
        )
    }

    @Test("extractComponents uses version tag when available for version, but keeps pedigree as commit sha")
    func extractComponentsUsesVersionTagWhenAvailable() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components

        // Find a version-based dependency (swift-argument-parser uses version "1.5.1")
        let swiftSystemComponent = components.first { component in component.id.value == "swift-system" }

        let versionComponent = try #require(swiftSystemComponent, "component should be found")

        let commits = try #require(
            versionComponent.originator.commits,
            "component should have commit information"
        )
        #expect(!commits.isEmpty, "component should have at least one commit")

        let commit = commits[0]
        #expect(!commit.sha.isEmpty, "Commit SHA should not be empty")
        #expect(
            commit.repository == "https://github.com/apple/swift-system.git",
            "Repository URL should match"
        )

        #expect(
            versionComponent.version.revision == "1.3.2",
            "Component version should be the version tag for version-based dependency"
        )
        #expect(
            versionComponent.version.revision != commit.sha,
            "Component version should not be the commit SHA for version-based dependency"
        )
    }

    @Test("extractComponents with product filter")
    func extractComponentsWithProductFilter() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let productName = "SwiftPMDataModel"
        let components = try await extractor.extractDependencies(product: productName).components
        let allComponents = try await extractor.extractDependencies().components

        // Verify using the helper function
        self.verifyComponents(
            components: components,
            graph: graph,
            expectations: Self.spmExpectations,
            filter: .all,
            product: productName
        )

        #expect(components.count < allComponents.count)

        let componentIDs = Set(components.map(\.id.value))
        #expect(components.count > 0)
        #expect(components.count < allComponents.count)

        let expectedComponentIDs: Set<String> = [
            "swift-toolchain-sqlite", "swift-certificates:X509", "swift-crypto",
            "swift-tools-support-core", "swift-collections:Collections",
            "swift-system", "swift-certificates", "swift-package-manager",
            "swift-collections", "swift-system:SystemPackage",
            "swift-collections:BitCollections", "swift-crypto:Crypto",
            "swift-tools-support-core:SwiftToolsSupport-auto", "swift-asn1",
            "swift-package-manager:SwiftPMDataModel", "swift-asn1:SwiftASN1",
            "swift-toolchain-sqlite:SwiftToolchainCSQLite", "swift-crypto:_CryptoExtras",
        ]
        #expect(componentIDs == expectedComponentIDs)

        let componentIDsList = components.map(\.id)
        let uniqueIDs = Set(componentIDsList)
        #expect(componentIDsList.count == uniqueIDs.count)
    }

    // MARK: - Revision Tests

    @Test("Root package components should not have 'unknown' versions")
    func rootPackageComponentsShouldNotHaveUnknownVersions() async throws {
        let (spmRepo, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components

        let rootPackage = try #require(graph.rootPackages.first)
        let rootPackageID = rootPackage.identity.description

        let actualRevision = try spmRepo.getCurrentRevision().identifier

        let rootComponents = components.filter { component in
            component.id.value == rootPackageID || component.id.value.hasPrefix("\(rootPackageID):")
        }

        #expect(!rootComponents.isEmpty, "Should have root package components")

        for component in rootComponents {
            #expect(component.version.revision == actualRevision)
            #expect(
                component.originator.commits != nil,
                "Root package component '\(component.id.value)' should have commit information"
            )
            if let commits = component.originator.commits {
                #expect(!commits.isEmpty)
                #expect(commits[0].sha == actualRevision)
            }
        }
    }

    @Test("Root package components should include only origin remote in originator")
    func rootPackageComponentsShouldIncludeAllRemotesInOriginator() async throws {
        let (_, spmPath) = try SBOMTestRepo.setupSPMTestRepo()
        defer { try? SBOMTestRepo.cleanup(spmPath) }

        // Add a second remote to test multiple remotes
        try await Process.checkNonZeroExit(
            args: Git.tool,
            "-C",
            spmPath.pathString,
            "remote",
            "add",
            "upstream",
            "https://github.com/fork/swift-package-manager.git"
        )

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: spmPath.pathString)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components

        let rootPackage = try #require(graph.rootPackages.first)
        let rootPackageID = rootPackage.identity.description

        let rootComponents = components.filter { component in
            component.id.value == rootPackageID || component.id.value.hasPrefix("\(rootPackageID):")
        }

        #expect(!rootComponents.isEmpty, "Should have root package components")

        for component in rootComponents {
            let commits = try #require(
                component.originator.commits,
                "Root package component '\(component.id.value)' should have commit information"
            )
            #expect(commits.count == 1)
        }
    }

    // MARK: - Filter Tests
    @Test("Filter.all includes all components")
    func filterAllIncludesAllComponents() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let dependencies = try await extractor.extractDependencies(filter: .all)
        
        self.verifyComponents(
            components: dependencies.components,
            graph: graph,
            expectations: Self.simpleExpectations,
            filter: .all
        )
    }
    
    @Test("Filter.product includes only product components and primary component")
    func filterProductIncludesOnlyProductsAndPrimaryComponent() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        
        let dependencies = try await extractor.extractDependencies(filter: .product)
        
        self.verifyComponents(
            components: dependencies.components,
            graph: graph,
            expectations: Self.spmExpectations,
            filter: .product
        )
    }
    
    @Test("Filter.package includes only package components")
    func filterPackageIncludesOnlyPackages() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let dependencies = try await extractor.extractDependencies(filter: .package)
        self.verifyComponents(
            components: dependencies.components,
            graph: graph,
            expectations: Self.spmExpectations,
            filter: .package
        )
    }

    @Test("Filter.all with SPM graph includes all entity types")
    func filterAllWithSPMGraph() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let dependencies = try await extractor.extractDependencies(filter: .all)
        self.verifyComponents(
            components: dependencies.components,
            graph: graph,
            expectations: Self.spmExpectations,
            filter: .all,
        )
    }
    

    @Test("Filter.product with specific product contains only product components")
    func filterProductWithSpecificProduct() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        
        let productName = "SwiftPMPackageCollections"
        let dependencies = try await extractor.extractDependencies(product: productName, filter: .product)
        self.verifyComponents(
            components: dependencies.components,
            graph: graph,
            expectations: Self.spmExpectations,
            filter: .product,
            product: productName
        )
    }
    
    @Test("Filter.package with specific product contains only package components and product primary component")
    func filterPackageWithSpecificProduct() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        
        let productName = "SwiftPMPackageCollections"
        let dependencies = try await extractor.extractDependencies(product: productName, filter: .package)
        self.verifyComponents(
            components: dependencies.components,
            graph: graph,
            expectations: Self.spmExpectations,
            filter: .package,
            product: productName
        )
    }

    // MARK: - Mock Registry Tests
    
    @Test("extractComponents from mock registry package")
    func extractComponentsFromMockRegistryPackage() async throws {
        let fs = InMemoryFileSystem()
        
        // Create mock registry
        let registry = MockRegistry(
            filesystem: fs,
            identityResolver: DefaultIdentityResolver(),
            checksumAlgorithm: MockHashAlgorithm(),
            fingerprintStorage: MockPackageFingerprintStorage(),
            signingEntityStorage: MockPackageSigningEntityStorage()
        )
        
        // Setup registry package
        let registryPackageIdentity: PackageIdentity = .plain("example.TestLibrary")
        let registryPackageVersion: Version = "1.0.0"
        let registryPackageSource = InMemoryRegistryPackageSource(
            fileSystem: fs,
            path: .root.appending(components: "registry", "server", registryPackageIdentity.description)
        )
        try registryPackageSource.writePackageContent(
            targets: ["TestLibrary"],
            toolsVersion: .v5_9
        )
        
        // Add package to registry
        registry.addPackage(
            identity: registryPackageIdentity,
            versions: [registryPackageVersion],
            sourceControlURLs: [URL("https://github.com/example/TestLibrary")],
            source: registryPackageSource
        )
        
        // Create registry dependency package first
        let registryModule = SBOMTestModulesGraph.createSwiftModule(
            name: "TestLibrary",
            type: .library
        )
        let registryProduct = try Product(
            package: registryPackageIdentity,
            name: "TestLibrary",
            type: .library(.automatic),
            modules: [registryModule]
        )
        let registryPackage = SBOMTestModulesGraph.createPackage(
            identity: registryPackageIdentity,
            displayName: "TestLibrary",
            path: "/registry/TestLibrary",
            modules: [registryModule],
            products: [registryProduct]
        )
        
        // Create resolved modules and products for registry package
        let registryResolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: registryPackageIdentity,
            module: registryModule
        )
        let registryResolvedProduct = SBOMTestModulesGraph.createResolvedProduct(
            packageIdentity: registryPackageIdentity,
            product: registryProduct,
            modules: IdentifiableSet([registryResolvedModule])
        )
        
        // Create a root package that depends on the registry package
        let rootPackageIdentity = PackageIdentity.plain("MyApp")
        let rootModule = SBOMTestModulesGraph.createSwiftModule(
            name: "MyApp",
            type: .executable
        )
        let rootProduct = try Product(
            package: rootPackageIdentity,
            name: "App",
            type: .executable,
            modules: [rootModule]
        )
        let rootPackage = SBOMTestModulesGraph.createPackage(
            identity: rootPackageIdentity,
            displayName: "MyApp",
            path: "/MyApp",
            modules: [rootModule],
            products: [rootProduct]
        )
        
        // Create resolved modules with dependency on registry product
        let rootResolvedModule = SBOMTestModulesGraph.createResolvedModule(
            packageIdentity: rootPackageIdentity,
            module: rootModule,
            dependencies: [
                .product(registryResolvedProduct, conditions: [])
            ]
        )
        let rootResolvedProduct = SBOMTestModulesGraph.createResolvedProduct(
            packageIdentity: rootPackageIdentity,
            product: rootProduct,
            modules: IdentifiableSet([rootResolvedModule])
        )
        
        // Create resolved packages with registry metadata
        let registryURL = URL("http://localhost/registry/mock")
        let registryMetadata = RegistryReleaseMetadata(
            source: .registry(registryURL),
            metadata: .init(
                author: nil,
                description: "Test library from registry",
                licenseURL: nil,
                readmeURL: nil,
                scmRepositoryURLs: [SourceControlURL("https://github.com/example/TestLibrary")]
            ),
            signature: nil
        )
        
        let rootResolvedPackage = SBOMTestModulesGraph.createResolvedPackage(
            package: rootPackage,
            modules: IdentifiableSet([rootResolvedModule]),
            products: [rootResolvedProduct],
            dependencies: [registryPackageIdentity]
        )
        
        let registryResolvedPackage = ResolvedPackage(
            underlying: registryPackage,
            defaultLocalization: nil,
            supportedPlatforms: [],
            dependencies: [],
            enabledTraits: nil,
            modules: IdentifiableSet([registryResolvedModule]),
            products: [registryResolvedProduct],
            registryMetadata: registryMetadata,
            platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
        )
        
        // Create package references
        let registryPackageRef = PackageReference.registry(identity: registryPackageIdentity)
        
        // Create modules graph
        let graph = try ModulesGraph(
            rootPackages: [rootResolvedPackage],
            rootDependencies: [registryResolvedPackage],
            packages: IdentifiableSet([rootResolvedPackage, registryResolvedPackage]),
            dependencies: [registryPackageRef],
            binaryArtifacts: [:]
        )
        
        // Create store with registry package
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        store.track(
            packageRef: registryPackageRef,
            state: .version(registryPackageVersion, revision: "abc123")
        )
        
        // Extract components
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let components = try await extractor.extractDependencies().components
        
        // Verify components - should have root package, root product, registry package, and registry product
        #expect(components.count >= 3, "Should have at least root package, root product, and registry product")
        
        // Find registry product component (not package - products are what get extracted as dependencies)
        let registryProductComponent = components.first {
            $0.id.value.contains("TestLibrary") && $0.entity == .product
        }
        let foundRegistryProduct = try #require(registryProductComponent, "Registry product component should be found. Available: \(components.map { "\($0.id.value) (\($0.entity))" }.joined(separator: ", "))")
        
        // Verify registry product properties
        #expect(foundRegistryProduct.name == "TestLibrary")
        #expect(foundRegistryProduct.version.revision == "1.0.0")
        #expect(foundRegistryProduct.entity == .product)
        
        // Find registry package component
        let registryPackageComponent = components.first {
            $0.id.value == registryPackageIdentity.description && $0.entity == .package
        }
        let foundRegistryPackage = try #require(registryPackageComponent, "Registry package component should be found")
        
        // Verify registry package properties
        #expect(foundRegistryPackage.name == "example.TestLibrary")
        #expect(foundRegistryPackage.version.revision == "1.0.0")
        #expect(foundRegistryPackage.entity == .package)
        
        // Verify registry entry in version
        let registryEntry = try #require(
            foundRegistryPackage.version.entry,
            "Registry package should have registry entry"
        )
        #expect(registryEntry.url == registryURL)
        #expect(registryEntry.scope == "example")
        #expect(registryEntry.name == "TestLibrary")
        #expect(registryEntry.version == "1.0.0")
        
        // Verify registry entry in originator
        let originatorEntries = try #require(
            foundRegistryPackage.originator.entries,
            "Registry package should have originator entries"
        )
        #expect(originatorEntries[0].url == registryURL)
        
        // Verify PURL is correct for registry package
        let expectedPURL = PURL(
            scheme: "pkg",
            type: "swift",
            namespace: "example",
            name: "TestLibrary",
            version: "1.0.0"
        )
        #expect(foundRegistryPackage.purl == expectedPURL)
    }
}
