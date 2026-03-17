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
    // MARK: - swift-system Package

    static func createSPMSwiftSystemPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-system")

        // Modules
        let cSystemModule = self.createSwiftModule(name: "CSystem")
        let systemPackageModule = self.createSwiftModule(name: "SystemPackage")

        // Products
        let systemPackageProduct = try Product(
            package: identity,
            name: "SystemPackage",
            type: .library(.automatic),
            modules: [systemPackageModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-system",
            path: "/swift-system",
            modules: [cSystemModule, systemPackageModule],
            products: [systemPackageProduct]
        )

        // Resolved modules
        let resolvedCSystemModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cSystemModule
        )

        let resolvedSystemPackageModule = self.createResolvedModule(
            packageIdentity: identity,
            module: systemPackageModule,
            dependencies: [
                .module(resolvedCSystemModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedSystemPackageProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: systemPackageProduct,
            modules: IdentifiableSet([resolvedSystemPackageModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedCSystemModule, resolvedSystemPackageModule]),
            products: [resolvedSystemPackageProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-system.git"))
        )

        return (
            package: package,
            modules: [cSystemModule, systemPackageModule],
            products: [systemPackageProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedCSystemModule, resolvedSystemPackageModule],
            resolvedProducts: [resolvedSystemPackageProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-collections Package

    static func createSPMSwiftCollectionsPackage() throws -> (
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
        let bitCollectionsModule = self.createSwiftModule(name: "BitCollections")
        let dequeModuleModule = self.createSwiftModule(name: "DequeModule")
        let hashTreeCollectionsModule = self.createSwiftModule(name: "HashTreeCollections")
        let heapModuleModule = self.createSwiftModule(name: "HeapModule")
        let orderedCollectionsModule = self.createSwiftModule(name: "OrderedCollections")
        let ropeModuleModule = self.createSwiftModule(name: "_RopeModule")
        let collectionsModule = self.createSwiftModule(name: "Collections")

        // Products
        let bitCollectionsProduct = try Product(
            package: identity,
            name: "BitCollections",
            type: .library(.automatic),
            modules: [bitCollectionsModule]
        )

        let dequeModuleProduct = try Product(
            package: identity,
            name: "DequeModule",
            type: .library(.automatic),
            modules: [dequeModuleModule]
        )

        let hashTreeCollectionsProduct = try Product(
            package: identity,
            name: "HashTreeCollections",
            type: .library(.automatic),
            modules: [hashTreeCollectionsModule]
        )

        let heapModuleProduct = try Product(
            package: identity,
            name: "HeapModule",
            type: .library(.automatic),
            modules: [heapModuleModule]
        )

        let orderedCollectionsProduct = try Product(
            package: identity,
            name: "OrderedCollections",
            type: .library(.automatic),
            modules: [orderedCollectionsModule]
        )

        let ropeModuleProduct = try Product(
            package: identity,
            name: "_RopeModule",
            type: .library(.automatic),
            modules: [ropeModuleModule]
        )

        let collectionsProduct = try Product(
            package: identity,
            name: "Collections",
            type: .library(.automatic),
            modules: [collectionsModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-collections",
            path: "/swift-collections",
            modules: [
                internalCollectionsUtilitiesModule, bitCollectionsModule, dequeModuleModule,
                hashTreeCollectionsModule, heapModuleModule, orderedCollectionsModule,
                ropeModuleModule, collectionsModule,
            ],
            products: [
                bitCollectionsProduct, dequeModuleProduct, hashTreeCollectionsProduct,
                heapModuleProduct, orderedCollectionsProduct, ropeModuleProduct, collectionsProduct,
            ]
        )

        // Resolved modules
        let resolvedInternalCollectionsUtilitiesModule = self.createResolvedModule(
            packageIdentity: identity,
            module: internalCollectionsUtilitiesModule
        )

        let resolvedBitCollectionsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: bitCollectionsModule,
            dependencies: [
                .module(resolvedInternalCollectionsUtilitiesModule, conditions: []),
            ]
        )

        let resolvedDequeModuleModule = self.createResolvedModule(
            packageIdentity: identity,
            module: dequeModuleModule,
            dependencies: [
                .module(resolvedInternalCollectionsUtilitiesModule, conditions: []),
            ]
        )

        let resolvedHashTreeCollectionsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: hashTreeCollectionsModule,
            dependencies: [
                .module(resolvedInternalCollectionsUtilitiesModule, conditions: []),
            ]
        )

        let resolvedHeapModuleModule = self.createResolvedModule(
            packageIdentity: identity,
            module: heapModuleModule,
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

        let resolvedRopeModuleModule = self.createResolvedModule(
            packageIdentity: identity,
            module: ropeModuleModule,
            dependencies: [
                .module(resolvedInternalCollectionsUtilitiesModule, conditions: []),
            ]
        )

        let resolvedCollectionsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: collectionsModule,
            dependencies: [
                .module(resolvedBitCollectionsModule, conditions: []),
                .module(resolvedDequeModuleModule, conditions: []),
                .module(resolvedHashTreeCollectionsModule, conditions: []),
                .module(resolvedHeapModuleModule, conditions: []),
                .module(resolvedOrderedCollectionsModule, conditions: []),
                .module(resolvedRopeModuleModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedBitCollectionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: bitCollectionsProduct,
            modules: IdentifiableSet([resolvedBitCollectionsModule])
        )

        let resolvedDequeModuleProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: dequeModuleProduct,
            modules: IdentifiableSet([resolvedDequeModuleModule])
        )

        let resolvedHashTreeCollectionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: hashTreeCollectionsProduct,
            modules: IdentifiableSet([resolvedHashTreeCollectionsModule])
        )

        let resolvedHeapModuleProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: heapModuleProduct,
            modules: IdentifiableSet([resolvedHeapModuleModule])
        )

        let resolvedOrderedCollectionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: orderedCollectionsProduct,
            modules: IdentifiableSet([resolvedOrderedCollectionsModule])
        )

        let resolvedRopeModuleProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: ropeModuleProduct,
            modules: IdentifiableSet([resolvedRopeModuleModule])
        )

        let resolvedCollectionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: collectionsProduct,
            modules: IdentifiableSet([resolvedCollectionsModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedInternalCollectionsUtilitiesModule, resolvedBitCollectionsModule,
                resolvedDequeModuleModule, resolvedHashTreeCollectionsModule, resolvedHeapModuleModule,
                resolvedOrderedCollectionsModule, resolvedRopeModuleModule, resolvedCollectionsModule,
            ]),
            products: [
                resolvedBitCollectionsProduct, resolvedDequeModuleProduct, resolvedHashTreeCollectionsProduct,
                resolvedHeapModuleProduct, resolvedOrderedCollectionsProduct, resolvedRopeModuleProduct,
                resolvedCollectionsProduct,
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-collections.git"))
        )

        return (
            package: package,
            modules: [
                internalCollectionsUtilitiesModule, bitCollectionsModule, dequeModuleModule,
                hashTreeCollectionsModule, heapModuleModule, orderedCollectionsModule,
                ropeModuleModule, collectionsModule,
            ],
            products: [
                bitCollectionsProduct, dequeModuleProduct, hashTreeCollectionsProduct,
                heapModuleProduct, orderedCollectionsProduct, ropeModuleProduct, collectionsProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedInternalCollectionsUtilitiesModule, resolvedBitCollectionsModule,
                resolvedDequeModuleModule, resolvedHashTreeCollectionsModule, resolvedHeapModuleModule,
                resolvedOrderedCollectionsModule, resolvedRopeModuleModule, resolvedCollectionsModule,
            ],
            resolvedProducts: [
                resolvedBitCollectionsProduct, resolvedDequeModuleProduct, resolvedHashTreeCollectionsProduct,
                resolvedHeapModuleProduct, resolvedOrderedCollectionsProduct, resolvedRopeModuleProduct,
                resolvedCollectionsProduct,
            ],
            packageRef: packageRef
        )
    }

    // MARK: - swift-argument-parser Package

    static func createSPMSwiftArgumentParserPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-argument-parser")

        // Modules
        let argumentParserToolInfoModule = self.createSwiftModule(name: "ArgumentParserToolInfo")
        let argumentParserModule = self.createSwiftModule(name: "ArgumentParser")
        let generateDoccReferenceModule = self.createSwiftModule(name: "GenerateDoccReference", type: .plugin)
        let generateManualModule = self.createSwiftModule(name: "GenerateManual", type: .plugin)
        let generateDoccReferenceExecModule = self.createSwiftModule(name: "generate-docc-reference", type: .executable)
        let generateManualExecModule = self.createSwiftModule(name: "generate-manual", type: .executable)

        // Products
        let argumentParserProduct = try Product(
            package: identity,
            name: "ArgumentParser",
            type: .library(.automatic),
            modules: [argumentParserModule]
        )

        let generateDoccReferenceProduct = try Product(
            package: identity,
            name: "GenerateDoccReference",
            type: .plugin,
            modules: [generateDoccReferenceModule]
        )

        let generateManualProduct = try Product(
            package: identity,
            name: "GenerateManual",
            type: .plugin,
            modules: [generateManualModule]
        )

        let generateDoccReferenceExecProduct = try Product(
            package: identity,
            name: "generate-docc-reference",
            type: .executable,
            modules: [generateDoccReferenceExecModule]
        )

        let generateManualExecProduct = try Product(
            package: identity,
            name: "generate-manual",
            type: .executable,
            modules: [generateManualExecModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-argument-parser",
            path: "/swift-argument-parser",
            modules: [
                argumentParserToolInfoModule, argumentParserModule, generateDoccReferenceModule,
                generateManualModule, generateDoccReferenceExecModule, generateManualExecModule,
            ],
            products: [
                argumentParserProduct, generateDoccReferenceProduct, generateManualProduct,
                generateDoccReferenceExecProduct, generateManualExecProduct,
            ]
        )

        // Resolved modules
        let resolvedArgumentParserToolInfoModule = self.createResolvedModule(
            packageIdentity: identity,
            module: argumentParserToolInfoModule
        )

        let resolvedArgumentParserModule = self.createResolvedModule(
            packageIdentity: identity,
            module: argumentParserModule,
            dependencies: [
                .module(resolvedArgumentParserToolInfoModule, conditions: []),
            ]
        )

        let resolvedGenerateDoccReferenceExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateDoccReferenceExecModule,
            dependencies: [
                .module(resolvedArgumentParserModule, conditions: []),
                .module(resolvedArgumentParserToolInfoModule, conditions: []),
            ]
        )

        let resolvedGenerateManualExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateManualExecModule,
            dependencies: [
                .module(resolvedArgumentParserModule, conditions: []),
                .module(resolvedArgumentParserToolInfoModule, conditions: []),
            ]
        )

        let resolvedGenerateDoccReferenceModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateDoccReferenceModule,
            dependencies: [
                .module(resolvedGenerateDoccReferenceExecModule, conditions: []),
            ]
        )

        let resolvedGenerateManualModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateManualModule,
            dependencies: [
                .module(resolvedGenerateManualExecModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedArgumentParserProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: argumentParserProduct,
            modules: IdentifiableSet([resolvedArgumentParserModule])
        )

        let resolvedGenerateDoccReferenceProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: generateDoccReferenceProduct,
            modules: IdentifiableSet([resolvedGenerateDoccReferenceModule])
        )

        let resolvedGenerateManualProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: generateManualProduct,
            modules: IdentifiableSet([resolvedGenerateManualModule])
        )

        let resolvedGenerateDoccReferenceExecProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: generateDoccReferenceExecProduct,
            modules: IdentifiableSet([resolvedGenerateDoccReferenceExecModule])
        )

        let resolvedGenerateManualExecProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: generateManualExecProduct,
            modules: IdentifiableSet([resolvedGenerateManualExecModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedArgumentParserToolInfoModule, resolvedArgumentParserModule,
                resolvedGenerateDoccReferenceModule, resolvedGenerateManualModule,
                resolvedGenerateDoccReferenceExecModule, resolvedGenerateManualExecModule,
            ]),
            products: [
                resolvedArgumentParserProduct, resolvedGenerateDoccReferenceProduct,
                resolvedGenerateManualProduct, resolvedGenerateDoccReferenceExecProduct,
                resolvedGenerateManualExecProduct,
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-argument-parser.git"))
        )

        return (
            package: package,
            modules: [
                argumentParserToolInfoModule, argumentParserModule, generateDoccReferenceModule,
                generateManualModule, generateDoccReferenceExecModule, generateManualExecModule,
            ],
            products: [
                argumentParserProduct, generateDoccReferenceProduct, generateManualProduct,
                generateDoccReferenceExecProduct, generateManualExecProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedArgumentParserToolInfoModule, resolvedArgumentParserModule,
                resolvedGenerateDoccReferenceModule, resolvedGenerateManualModule,
                resolvedGenerateDoccReferenceExecModule, resolvedGenerateManualExecModule,
            ],
            resolvedProducts: [
                resolvedArgumentParserProduct, resolvedGenerateDoccReferenceProduct,
                resolvedGenerateManualProduct, resolvedGenerateDoccReferenceExecProduct,
                resolvedGenerateManualExecProduct,
            ],
            packageRef: packageRef
        )
    }

    // MARK: - swift-toolchain-sqlite Package

    static func createSPMSwiftToolchainSQLitePackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-toolchain-sqlite")

        // Modules
        let swiftToolchainCSQLiteModule = self.createSwiftModule(name: "SwiftToolchainCSQLite")
        let sqliteModule = self.createSwiftModule(name: "sqlite", type: .executable)

        // Products
        let swiftToolchainCSQLiteProduct = try Product(
            package: identity,
            name: "SwiftToolchainCSQLite",
            type: .library(.automatic),
            modules: [swiftToolchainCSQLiteModule]
        )

        let sqliteProduct = try Product(
            package: identity,
            name: "sqlite",
            type: .executable,
            modules: [sqliteModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-toolchain-sqlite",
            path: "/swift-toolchain-sqlite",
            modules: [swiftToolchainCSQLiteModule, sqliteModule],
            products: [swiftToolchainCSQLiteProduct, sqliteProduct]
        )

        // Resolved modules
        let resolvedSwiftToolchainCSQLiteModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftToolchainCSQLiteModule
        )

        let resolvedSQLiteModule = self.createResolvedModule(
            packageIdentity: identity,
            module: sqliteModule,
            dependencies: [
                .module(resolvedSwiftToolchainCSQLiteModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedSwiftToolchainCSQLiteProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftToolchainCSQLiteProduct,
            modules: IdentifiableSet([resolvedSwiftToolchainCSQLiteModule])
        )

        let resolvedSQLiteProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: sqliteProduct,
            modules: IdentifiableSet([resolvedSQLiteModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedSwiftToolchainCSQLiteModule, resolvedSQLiteModule]),
            products: [resolvedSwiftToolchainCSQLiteProduct, resolvedSQLiteProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-toolchain-sqlite.git"))
        )

        return (
            package: package,
            modules: [swiftToolchainCSQLiteModule, sqliteModule],
            products: [swiftToolchainCSQLiteProduct, sqliteProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedSwiftToolchainCSQLiteModule, resolvedSQLiteModule],
            resolvedProducts: [resolvedSwiftToolchainCSQLiteProduct, resolvedSQLiteProduct],
            packageRef: packageRef
        )
    }
}
