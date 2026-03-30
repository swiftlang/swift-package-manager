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
@testable import SBOMModel

/// A test case that bundles a ModulesGraph with its expected test outcomes
struct SBOMTestCase {
    let name: String
    let graph: ModulesGraph
    let store: ResolvedPackagesStore
    let expectations: TestExpectations
    
    struct TestExpectations {
        let totalComponentCount: Int
        let expectedPackageIds: Set<String>
        let rootPackage: String
        let rootPackagePrefix: String
        let expectedRootProductCount: Int
        let expectedRootProductNames: Set<String>
    }
    
    /// Creates a test case for the simple test graph
    static func createSimpleTestCase() throws -> SBOMTestCase {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let expectations = TestExpectations(
            totalComponentCount: 4,
            expectedPackageIds: Set(["MyApp", "Utils"]),
            rootPackage: "MyApp",
            rootPackagePrefix: "MyApp:",
            expectedRootProductCount: 1,
            expectedRootProductNames: Set(["App"])
        )
        return SBOMTestCase(
            name: "Simple",
            graph: graph,
            store: store,
            expectations: expectations
        )
    }
    
    /// Creates a test case for the SPM test graph
    static func createSPMTestCase(rootPath: String = "/swift-package-manager") throws -> SBOMTestCase {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph(rootPath: rootPath)
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let expectations = TestExpectations(
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
            ])
        )
        return SBOMTestCase(
            name: "SPM",
            graph: graph,
            store: store,
            expectations: expectations
        )
    }
    
    /// Creates a test case for the Swiftly test graph
    static func createSwiftlyTestCase(rootPath: String = "/tmp/swiftly-mock") throws -> SBOMTestCase {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph(rootPath: rootPath)
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let expectations = TestExpectations(
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
            ])
        )
        return SBOMTestCase(
            name: "Swiftly",
            graph: graph,
            store: store,
            expectations: expectations
        )
    }
}

enum SBOMTestModulesGraph {
    // MARK: - Helper functions

    static func createSwiftModule(
        name: String,
        dependencies: [Module.Dependency] = [],
        packageAccess: Bool = false,
        type: Module.Kind = .library
    ) -> SwiftModule {
        let path = AbsolutePath("/\(name)")
        let sources = Sources(paths: [], root: path)
        return SwiftModule(
            name: name,
            type: type,
            path: path,
            sources: sources,
            dependencies: dependencies,
            packageAccess: packageAccess,
            usesUnsafeFlags: false,
            implicit: false
        )
    }

    static func createPackage(
        identity: PackageIdentity,
        displayName: String,
        path: String,
        modules: [Module],
        products: [Product]
    ) -> Package {
        let manifest = Manifest.createFileSystemManifest(
            displayName: displayName,
            path: AbsolutePath(path),
            toolsVersion: .vNext
        )

        return Package(
            identity: identity,
            manifest: manifest,
            path: AbsolutePath(path),
            targets: modules,
            products: products,
            targetSearchPath: AbsolutePath(path).appending("Sources"),
            testTargetSearchPath: AbsolutePath(path).appending("Tests")
        )
    }

    static func createResolvedModule(
        packageIdentity: PackageIdentity,
        module: Module,
        dependencies: [ResolvedModule.Dependency] = [],
        supportedPlatforms: [SupportedPlatform] = []
    ) -> ResolvedModule {
        ResolvedModule(
            packageIdentity: packageIdentity,
            underlying: module,
            dependencies: dependencies,
            defaultLocalization: nil,
            supportedPlatforms: supportedPlatforms,
            platformConstraint: .all,
            platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
        )
    }

    static func createResolvedProduct(
        packageIdentity: PackageIdentity,
        product: Product,
        modules: IdentifiableSet<ResolvedModule>
    ) -> ResolvedProduct {
        ResolvedProduct(
            packageIdentity: packageIdentity,
            product: product,
            modules: modules
        )
    }

    static func createResolvedPackage(
        package: Package,
        modules: IdentifiableSet<ResolvedModule>,
        products: [ResolvedProduct],
        dependencies: [PackageIdentity] = [],
        enabledTraits: Set<String>? = nil
    ) -> ResolvedPackage {
        ResolvedPackage(
            underlying: package,
            defaultLocalization: nil,
            supportedPlatforms: [],
            dependencies: dependencies,
            enabledTraits: enabledTraits,
            modules: modules,
            products: products,
            registryMetadata: nil,
            platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
        )
    }

    static func createProduct(
        name: String,
        type: ProductType,
        moduleType: Module.Kind = .library
    ) throws -> ResolvedProduct {
        let packageName = PackageIdentity.plain("Package\(name)")
        let module = self.createSwiftModule(
            name: "\(name)Module",
            type: moduleType
        )
        let product = try Product(
            package: packageName,
            name: name,
            type: type,
            modules: [module]
        )
        let resolvedModule = self.createResolvedModule(
            packageIdentity: packageName,
            module: module
        )
        return self.createResolvedProduct(
            packageIdentity: packageName,
            product: product,
            modules: IdentifiableSet([resolvedModule])
        )
    }

    static func createPackage(
        name: String,
        products: [ResolvedProduct],
        modules: [Module] = []
    ) throws -> ResolvedPackage {
        let packageName = PackageIdentity.plain("Package\(name)")
        let package = self.createPackage(
            identity: packageName,
            displayName: name,
            path: "/\(name)",
            modules: modules,
            products: products.map(\.underlying)
        )
        let resolvedModules = modules.map { module in
            self.createResolvedModule(
                packageIdentity: packageName,
                module: module
            )
        }
        return self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet(resolvedModules),
            products: products
        )
    }
}
