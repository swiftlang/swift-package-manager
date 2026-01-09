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
