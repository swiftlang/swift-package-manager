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

extension SBOMTestModulesGraph {
    // MARK: - swift-collections Package

    static func createSwiftCollectionsPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-collections")

        // Modules
        let internalCollectionsUtilitiesModule = self.createSwiftModule(name: "InternalCollectionsUtilities")
        let dequeModule = self.createSwiftModule(name: "DequeModule")
        let orderedCollectionsModule = self.createSwiftModule(name: "OrderedCollections")

        // Products
        let dequeProduct = try Product(
            package: identity,
            name: "DequeModule",
            type: .library(.automatic),
            modules: [dequeModule]
        )

        let orderedCollectionsProduct = try Product(
            package: identity,
            name: "OrderedCollections",
            type: .library(.automatic),
            modules: [orderedCollectionsModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-collections",
            path: "/swift-collections",
            modules: [internalCollectionsUtilitiesModule, dequeModule, orderedCollectionsModule],
            products: [dequeProduct, orderedCollectionsProduct]
        )

        // Resolved modules
        let resolvedInternalCollectionsUtilitiesModule = self.createResolvedModule(
            packageIdentity: identity,
            module: internalCollectionsUtilitiesModule
        )

        let resolvedDequeModule = self.createResolvedModule(
            packageIdentity: identity,
            module: dequeModule,
            dependencies: [
                .module(resolvedInternalCollectionsUtilitiesModule, conditions: []),
            ]
        )

        let resolvedOrderedCollectionsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: orderedCollectionsModule,
            dependencies: [
                .module(resolvedInternalCollectionsUtilitiesModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedDequeProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: dequeProduct,
            modules: IdentifiableSet([resolvedDequeModule])
        )

        let resolvedOrderedCollectionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: orderedCollectionsProduct,
            modules: IdentifiableSet([resolvedOrderedCollectionsModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedInternalCollectionsUtilitiesModule,
                resolvedDequeModule,
                resolvedOrderedCollectionsModule,
            ]),
            products: [resolvedDequeProduct, resolvedOrderedCollectionsProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-collections.git"))
        )

        return (
            package: package,
            modules: [internalCollectionsUtilitiesModule, dequeModule, orderedCollectionsModule],
            products: [dequeProduct, orderedCollectionsProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedInternalCollectionsUtilitiesModule,
                resolvedDequeModule,
                resolvedOrderedCollectionsModule,
            ],
            resolvedProducts: [resolvedDequeProduct, resolvedOrderedCollectionsProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-numerics Package

    static func createSwiftNumericsPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-numerics")

        // Modules
        let numericsShimsModule = self.createSwiftModule(name: "_NumericsShims")
        let realModule = self.createSwiftModule(name: "RealModule")

        // Products
        let realModuleProduct = try Product(
            package: identity,
            name: "RealModule",
            type: .library(.automatic),
            modules: [realModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-numerics",
            path: "/swift-numerics",
            modules: [numericsShimsModule, realModule],
            products: [realModuleProduct]
        )

        // Resolved modules
        let resolvedNumericsShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: numericsShimsModule
        )

        let resolvedRealModule = self.createResolvedModule(
            packageIdentity: identity,
            module: realModule,
            dependencies: [
                .module(resolvedNumericsShimsModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedRealModuleProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: realModuleProduct,
            modules: IdentifiableSet([resolvedRealModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedNumericsShimsModule, resolvedRealModule]),
            products: [resolvedRealModuleProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-numerics.git"))
        )

        return (
            package: package,
            modules: [numericsShimsModule, realModule],
            products: [realModuleProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedNumericsShimsModule, resolvedRealModule],
            resolvedProducts: [resolvedRealModuleProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-algorithms Package

    static func createSwiftAlgorithmsPackage(
        realModuleProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-algorithms")

        // Modules
        let algorithmsModule = self.createSwiftModule(name: "Algorithms")

        // Products
        let algorithmsProduct = try Product(
            package: identity,
            name: "Algorithms",
            type: .library(.automatic),
            modules: [algorithmsModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-algorithms",
            path: "/swift-algorithms",
            modules: [algorithmsModule],
            products: [algorithmsProduct]
        )

        // Resolved modules
        let resolvedAlgorithmsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: algorithmsModule,
            dependencies: [
                .product(realModuleProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedAlgorithmsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: algorithmsProduct,
            modules: IdentifiableSet([resolvedAlgorithmsModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedAlgorithmsModule]),
            products: [resolvedAlgorithmsProduct],
            dependencies: [PackageIdentity.plain("swift-numerics")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-algorithms.git"))
        )

        return (
            package: package,
            modules: [algorithmsModule],
            products: [algorithmsProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedAlgorithmsModule],
            resolvedProducts: [resolvedAlgorithmsProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-atomics Package

    static func createSwiftAtomicsPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-atomics")

        // Modules
        let atomicsShimsModule = self.createSwiftModule(name: "_AtomicsShims")
        let atomicsModule = self.createSwiftModule(name: "Atomics")

        // Products
        let atomicsProduct = try Product(
            package: identity,
            name: "Atomics",
            type: .library(.automatic),
            modules: [atomicsModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-atomics",
            path: "/swift-atomics",
            modules: [atomicsShimsModule, atomicsModule],
            products: [atomicsProduct]
        )

        // Resolved modules
        let resolvedAtomicsShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: atomicsShimsModule
        )

        let resolvedAtomicsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: atomicsModule,
            dependencies: [
                .module(resolvedAtomicsShimsModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedAtomicsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: atomicsProduct,
            modules: IdentifiableSet([resolvedAtomicsModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedAtomicsShimsModule, resolvedAtomicsModule]),
            products: [resolvedAtomicsProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-atomics.git"))
        )

        return (
            package: package,
            modules: [atomicsShimsModule, atomicsModule],
            products: [atomicsProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedAtomicsShimsModule, resolvedAtomicsModule],
            resolvedProducts: [resolvedAtomicsProduct],
            packageRef: packageRef
        )
    }
}
