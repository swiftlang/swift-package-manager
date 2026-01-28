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
    // MARK: - Root SPM Package - Part 4: Products & Assembly

    static func createSPMRootPackageComplete(
        rootPath: String = "/swift-package-manager",
        systemPackageProduct: ResolvedProduct,
        dequeModuleProduct: ResolvedProduct,
        orderedCollectionsProduct: ResolvedProduct,
        argumentParserProduct: ResolvedProduct,
        llbuildSwiftProduct: ResolvedProduct,
        swiftDriverProduct: ResolvedProduct,
        swiftToolsSupportAutoProduct: ResolvedProduct,
        tscBasicProduct: ResolvedProduct,
        tscTestSupportProduct: ResolvedProduct,
        cryptoProduct: ResolvedProduct,
        x509Product: ResolvedProduct,
        swiftToolchainCSQLiteProduct: ResolvedProduct,
        swiftIDEUtilsProduct: ResolvedProduct,
        swiftRefactorProduct: ResolvedProduct,
        swiftDiagnosticsProduct: ResolvedProduct,
        swiftParserProduct: ResolvedProduct,
        swiftSyntaxProduct: ResolvedProduct,
        swiftBuildProduct: ResolvedProduct,
        swbBuildServiceProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-package-manager")

        // MARK: - Create all module groups

        let coreResult = createSPMRootCoreModules(
            systemPackageProduct: systemPackageProduct,
            dequeModuleProduct: dequeModuleProduct,
            orderedCollectionsProduct: orderedCollectionsProduct,
            swiftToolchainCSQLiteProduct: swiftToolchainCSQLiteProduct,
            swiftToolsSupportAutoProduct: swiftToolsSupportAutoProduct,
            llbuildSwiftProduct: llbuildSwiftProduct,
            swiftDriverProduct: swiftDriverProduct,
            tscBasicProduct: tscBasicProduct,
            cryptoProduct: cryptoProduct,
            x509Product: x509Product
        )

        let commandResult = createSPMRootCommandModules(
            coreResolvedModules: coreResult.resolvedModules,
            argumentParserProduct: argumentParserProduct,
            orderedCollectionsProduct: orderedCollectionsProduct,
            tscBasicProduct: tscBasicProduct,
            swiftIDEUtilsProduct: swiftIDEUtilsProduct,
            swiftRefactorProduct: swiftRefactorProduct,
            swiftDiagnosticsProduct: swiftDiagnosticsProduct,
            swiftParserProduct: swiftParserProduct,
            swiftSyntaxProduct: swiftSyntaxProduct,
            swiftBuildProduct: swiftBuildProduct,
            swbBuildServiceProduct: swbBuildServiceProduct
        )

        let executableResult = createSPMRootExecutableModules(
            coreResolvedModules: coreResult.resolvedModules,
            commandResolvedModules: commandResult.resolvedModules,
            argumentParserProduct: argumentParserProduct,
            orderedCollectionsProduct: orderedCollectionsProduct
        )

        // Combine all modules
        let allModules = coreResult.modules + commandResult.modules + executableResult.modules
        let allResolvedModules = coreResult.resolvedModules + commandResult.resolvedModules + executableResult
            .resolvedModules

        // Extract specific resolved modules for products
        let resolvedBuildModule = coreResult.resolvedModules.first { $0.name == "Build" }!
        let resolvedLLBuildManifestModule = coreResult.resolvedModules.first { $0.name == "LLBuildManifest" }!
        let resolvedPackageCollectionsModule = coreResult.resolvedModules.first { $0.name == "PackageCollections" }!
        let resolvedPackageCollectionsModelModule = coreResult.resolvedModules
            .first { $0.name == "PackageCollectionsModel" }!
        let resolvedPackageCollectionsSigningModule = coreResult.resolvedModules
            .first { $0.name == "PackageCollectionsSigning" }!
        let resolvedPackageGraphModule = coreResult.resolvedModules.first { $0.name == "PackageGraph" }!
        let resolvedPackageLoadingModule = coreResult.resolvedModules.first { $0.name == "PackageLoading" }!
        let resolvedPackageMetadataModule = coreResult.resolvedModules.first { $0.name == "PackageMetadata" }!
        let resolvedPackageModelModule = coreResult.resolvedModules.first { $0.name == "PackageModel" }!
        let resolvedSPMLLBuildModule = coreResult.resolvedModules.first { $0.name == "SPMLLBuild" }!
        let resolvedSourceControlModule = coreResult.resolvedModules.first { $0.name == "SourceControl" }!
        let resolvedSourceKitLSPAPIModule = coreResult.resolvedModules.first { $0.name == "SourceKitLSPAPI" }!
        let resolvedWorkspaceModule = coreResult.resolvedModules.first { $0.name == "Workspace" }!

        let resolvedCompilerPluginSupportModule = commandResult.resolvedModules
            .first { $0.name == "CompilerPluginSupport" }!
        let resolvedPackageDescriptionModule = commandResult.resolvedModules.first { $0.name == "PackageDescription" }!
        let resolvedPackagePluginModule = commandResult.resolvedModules.first { $0.name == "PackagePlugin" }!
        let resolvedAppleProductTypesModule = commandResult.resolvedModules.first { $0.name == "AppleProductTypes" }!
        let resolvedXCBuildSupportModule = commandResult.resolvedModules.first { $0.name == "XCBuildSupport" }!

        // MARK: - Create Products

        // Dynamic library products
        let appleProductTypesProduct = try Product(
            package: identity,
            name: "AppleProductTypes",
            type: .library(.dynamic),
            modules: [allModules.first { $0.name == "AppleProductTypes" }!]
        )

        let packageDescriptionProduct = try Product(
            package: identity,
            name: "PackageDescription",
            type: .library(.dynamic),
            modules: [
                allModules.first { $0.name == "CompilerPluginSupport" }!,
                allModules.first { $0.name == "PackageDescription" }!,
            ]
        )

        let packagePluginProduct = try Product(
            package: identity,
            name: "PackagePlugin",
            type: .library(.dynamic),
            modules: [allModules.first { $0.name == "PackagePlugin" }!]
        )

        let swiftPMProduct = try Product(
            package: identity,
            name: "SwiftPM",
            type: .library(.dynamic),
            modules: [
                allModules.first { $0.name == "Build" }!,
                allModules.first { $0.name == "LLBuildManifest" }!,
                allModules.first { $0.name == "PackageCollections" }!,
                allModules.first { $0.name == "PackageCollectionsModel" }!,
                allModules.first { $0.name == "PackageGraph" }!,
                allModules.first { $0.name == "PackageLoading" }!,
                allModules.first { $0.name == "PackageMetadata" }!,
                allModules.first { $0.name == "PackageModel" }!,
                allModules.first { $0.name == "SPMLLBuild" }!,
                allModules.first { $0.name == "SourceControl" }!,
                allModules.first { $0.name == "SourceKitLSPAPI" }!,
                allModules.first { $0.name == "Workspace" }!,
            ]
        )

        // THE KEY PRODUCT: SwiftPMDataModel
        let swiftPMDataModelProduct = try Product(
            package: identity,
            name: "SwiftPMDataModel",
            type: .library(.dynamic),
            modules: [
                allModules.first { $0.name == "PackageCollections" }!,
                allModules.first { $0.name == "PackageCollectionsModel" }!,
                allModules.first { $0.name == "PackageGraph" }!,
                allModules.first { $0.name == "PackageLoading" }!,
                allModules.first { $0.name == "PackageMetadata" }!,
                allModules.first { $0.name == "PackageModel" }!,
                allModules.first { $0.name == "SourceControl" }!,
                allModules.first { $0.name == "Workspace" }!,
            ]
        )

        // Automatic library products
        let swiftPMAutoProduct = try Product(
            package: identity,
            name: "SwiftPM-auto",
            type: .library(.automatic),
            modules: [
                allModules.first { $0.name == "Build" }!,
                allModules.first { $0.name == "LLBuildManifest" }!,
                allModules.first { $0.name == "PackageCollections" }!,
                allModules.first { $0.name == "PackageCollectionsModel" }!,
                allModules.first { $0.name == "PackageGraph" }!,
                allModules.first { $0.name == "PackageLoading" }!,
                allModules.first { $0.name == "PackageMetadata" }!,
                allModules.first { $0.name == "PackageModel" }!,
                allModules.first { $0.name == "SPMLLBuild" }!,
                allModules.first { $0.name == "SourceControl" }!,
                allModules.first { $0.name == "SourceKitLSPAPI" }!,
                allModules.first { $0.name == "Workspace" }!,
            ]
        )

        let swiftPMDataModelAutoProduct = try Product(
            package: identity,
            name: "SwiftPMDataModel-auto",
            type: .library(.automatic),
            modules: [
                allModules.first { $0.name == "PackageCollections" }!,
                allModules.first { $0.name == "PackageCollectionsModel" }!,
                allModules.first { $0.name == "PackageGraph" }!,
                allModules.first { $0.name == "PackageLoading" }!,
                allModules.first { $0.name == "PackageMetadata" }!,
                allModules.first { $0.name == "PackageModel" }!,
                allModules.first { $0.name == "SourceControl" }!,
                allModules.first { $0.name == "Workspace" }!,
            ]
        )

        let packageCollectionsModelProduct = try Product(
            package: identity,
            name: "PackageCollectionsModel",
            type: .library(.automatic),
            modules: [allModules.first { $0.name == "PackageCollectionsModel" }!]
        )

        let swiftPMPackageCollectionsProduct = try Product(
            package: identity,
            name: "SwiftPMPackageCollections",
            type: .library(.automatic),
            modules: [
                allModules.first { $0.name == "PackageCollections" }!,
                allModules.first { $0.name == "PackageCollectionsModel" }!,
                allModules.first { $0.name == "PackageCollectionsSigning" }!,
                allModules.first { $0.name == "PackageModel" }!,
            ]
        )

        let xcBuildSupportProduct = try Product(
            package: identity,
            name: "XCBuildSupport",
            type: .library(.automatic),
            modules: [allModules.first { $0.name == "XCBuildSupport" }!]
        )

        // Executable products (simplified - just create them without listing all)
        let executableProducts = try [
            Product(
                package: identity,
                name: "dummy-swiftc",
                type: .executable,
                modules: [allModules.first { $0.name == "dummy-swiftc" }!]
            ),
            Product(
                package: identity,
                name: "package-info",
                type: .executable,
                modules: [allModules.first { $0.name == "package-info" }!]
            ),
            Product(
                package: identity,
                name: "swift-bootstrap",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-bootstrap" }!]
            ),
            Product(
                package: identity,
                name: "swift-build",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-build" }!]
            ),
            Product(
                package: identity,
                name: "swift-build-prebuilts",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-build-prebuilts" }!]
            ),
            Product(
                package: identity,
                name: "swift-experimental-sdk",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-experimental-sdk" }!]
            ),
            Product(
                package: identity,
                name: "swift-package",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-package" }!]
            ),
            Product(
                package: identity,
                name: "swift-package-collection",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-package-collection" }!]
            ),
            Product(
                package: identity,
                name: "swift-package-manager",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-package-manager" }!]
            ),
            Product(
                package: identity,
                name: "swift-package-registry",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-package-registry" }!]
            ),
            Product(
                package: identity,
                name: "swift-run",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-run" }!]
            ),
            Product(
                package: identity,
                name: "swift-sdk",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-sdk" }!]
            ),
            Product(
                package: identity,
                name: "swift-test",
                type: .executable,
                modules: [allModules.first { $0.name == "swift-test" }!]
            ),
            Product(
                package: identity,
                name: "swiftpm-testing-helper",
                type: .executable,
                modules: [allModules.first { $0.name == "swiftpm-testing-helper" }!]
            ),
        ]

        let allProducts = [
            appleProductTypesProduct, packageDescriptionProduct, packagePluginProduct,
            swiftPMProduct, swiftPMDataModelProduct, swiftPMAutoProduct, swiftPMDataModelAutoProduct,
            packageCollectionsModelProduct, swiftPMPackageCollectionsProduct, xcBuildSupportProduct,
        ] + executableProducts

        // MARK: - Create Package

        let package = self.createPackage(
            identity: identity,
            displayName: "SwiftPM",
            path: rootPath,
            modules: allModules,
            products: allProducts
        )

        // MARK: - Create Resolved Products

        let resolvedAppleProductTypesProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: appleProductTypesProduct,
            modules: IdentifiableSet([resolvedAppleProductTypesModule])
        )

        let resolvedPackageDescriptionProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: packageDescriptionProduct,
            modules: IdentifiableSet([resolvedCompilerPluginSupportModule, resolvedPackageDescriptionModule])
        )

        let resolvedPackagePluginProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: packagePluginProduct,
            modules: IdentifiableSet([resolvedPackagePluginModule])
        )

        let resolvedSwiftPMProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftPMProduct,
            modules: IdentifiableSet([
                resolvedBuildModule, resolvedLLBuildManifestModule, resolvedPackageCollectionsModule,
                resolvedPackageCollectionsModelModule, resolvedPackageGraphModule, resolvedPackageLoadingModule,
                resolvedPackageMetadataModule, resolvedPackageModelModule, resolvedSPMLLBuildModule,
                resolvedSourceControlModule, resolvedSourceKitLSPAPIModule, resolvedWorkspaceModule,
            ])
        )

        let resolvedSwiftPMDataModelProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftPMDataModelProduct,
            modules: IdentifiableSet([
                resolvedPackageCollectionsModule, resolvedPackageCollectionsModelModule, resolvedPackageGraphModule,
                resolvedPackageLoadingModule, resolvedPackageMetadataModule, resolvedPackageModelModule,
                resolvedSourceControlModule, resolvedWorkspaceModule,
            ])
        )

        let resolvedSwiftPMAutoProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftPMAutoProduct,
            modules: IdentifiableSet([
                resolvedBuildModule, resolvedLLBuildManifestModule, resolvedPackageCollectionsModule,
                resolvedPackageCollectionsModelModule, resolvedPackageGraphModule, resolvedPackageLoadingModule,
                resolvedPackageMetadataModule, resolvedPackageModelModule, resolvedSPMLLBuildModule,
                resolvedSourceControlModule, resolvedSourceKitLSPAPIModule, resolvedWorkspaceModule,
            ])
        )

        let resolvedSwiftPMDataModelAutoProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftPMDataModelAutoProduct,
            modules: IdentifiableSet([
                resolvedPackageCollectionsModule, resolvedPackageCollectionsModelModule, resolvedPackageGraphModule,
                resolvedPackageLoadingModule, resolvedPackageMetadataModule, resolvedPackageModelModule,
                resolvedSourceControlModule, resolvedWorkspaceModule,
            ])
        )

        let resolvedPackageCollectionsModelProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: packageCollectionsModelProduct,
            modules: IdentifiableSet([resolvedPackageCollectionsModelModule])
        )

        let resolvedSwiftPMPackageCollectionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftPMPackageCollectionsProduct,
            modules: IdentifiableSet([
                resolvedPackageCollectionsModule, resolvedPackageCollectionsModelModule,
                resolvedPackageCollectionsSigningModule, resolvedPackageModelModule,
            ])
        )

        let resolvedXCBuildSupportProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: xcBuildSupportProduct,
            modules: IdentifiableSet([resolvedXCBuildSupportModule])
        )

        // Create resolved executable products
        let resolvedExecutableProducts = executableProducts.map { product in
            self.createResolvedProduct(
                packageIdentity: identity,
                product: product,
                modules: IdentifiableSet([allResolvedModules.first { $0.name == product.name }!])
            )
        }

        let allResolvedProducts = [
            resolvedAppleProductTypesProduct, resolvedPackageDescriptionProduct, resolvedPackagePluginProduct,
            resolvedSwiftPMProduct, resolvedSwiftPMDataModelProduct, resolvedSwiftPMAutoProduct,
            resolvedSwiftPMDataModelAutoProduct, resolvedPackageCollectionsModelProduct,
            resolvedSwiftPMPackageCollectionsProduct, resolvedXCBuildSupportProduct,
        ] + resolvedExecutableProducts

        // MARK: - Create Resolved Package

        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet(allResolvedModules),
            products: allResolvedProducts,
            dependencies: [
                PackageIdentity.plain("swift-system"),
                PackageIdentity.plain("swift-collections"),
                PackageIdentity.plain("swift-argument-parser"),
                PackageIdentity.plain("swift-llbuild"),
                PackageIdentity.plain("swift-tools-support-core"),
                PackageIdentity.plain("swift-driver"),
                PackageIdentity.plain("swift-crypto"),
                PackageIdentity.plain("swift-certificates"),
                PackageIdentity.plain("swift-toolchain-sqlite"),
                PackageIdentity.plain("swift-syntax"),
                PackageIdentity.plain("swift-build"),
                PackageIdentity.plain("swift-docc-plugin"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .root(AbsolutePath(rootPath))
        )

        return (
            package: package,
            modules: allModules,
            products: allProducts,
            resolvedPackage: resolvedPackage,
            resolvedModules: allResolvedModules,
            resolvedProducts: allResolvedProducts,
            packageRef: packageRef
        )
    }
}
