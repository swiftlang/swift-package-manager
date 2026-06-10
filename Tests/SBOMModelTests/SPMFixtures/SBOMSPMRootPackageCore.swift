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
    // MARK: - Root SPM Package - Part 1: Core Library Modules

    /// Creates the core library modules for the root SwiftPM package
    /// These are the fundamental building blocks: Basics, PackageModel, PackageGraph, etc.
    static func createSPMRootCoreModules(
        systemPackageProduct: ResolvedProduct,
        dequeModuleProduct: ResolvedProduct,
        orderedCollectionsProduct: ResolvedProduct,
        swiftToolchainCSQLiteProduct: ResolvedProduct,
        swiftToolsSupportAutoProduct: ResolvedProduct,
        llbuildSwiftProduct: ResolvedProduct,
        swiftDriverProduct: ResolvedProduct,
        tscBasicProduct: ResolvedProduct,
        cryptoProduct: ResolvedProduct,
        x509Product: ResolvedProduct
    ) -> (
        modules: [Module],
        resolvedModules: [ResolvedModule]
    ) {
        let identity = PackageIdentity.plain("swift-package-manager")

        // MARK: - Create Core Modules

        let asyncFileSystemModule = self.createSwiftModule(name: "_AsyncFileSystem")
        let basicsModule = self.createSwiftModule(name: "Basics")
        let binarySymbolsModule = self.createSwiftModule(name: "BinarySymbols")
        let packageModelModule = self.createSwiftModule(name: "PackageModel")
        let sourceControlModule = self.createSwiftModule(name: "SourceControl")
        let packageLoadingModule = self.createSwiftModule(name: "PackageLoading")
        let packageGraphModule = self.createSwiftModule(name: "PackageGraph")
        let packageCollectionsModelModule = self.createSwiftModule(name: "PackageCollectionsModel")
        let packageCollectionsSigningModule = self.createSwiftModule(name: "PackageCollectionsSigning")
        let packageCollectionsModule = self.createSwiftModule(name: "PackageCollections")
        let packageMetadataModule = self.createSwiftModule(name: "PackageMetadata")
        let packageFingerprintModule = self.createSwiftModule(name: "PackageFingerprint")
        let packageSigningModule = self.createSwiftModule(name: "PackageSigning")
        let packageRegistryModule = self.createSwiftModule(name: "PackageRegistry")
        let spmBuildCoreModule = self.createSwiftModule(name: "SPMBuildCore")
        let workspaceModule = self.createSwiftModule(name: "Workspace")
        let llbuildManifestModule = self.createSwiftModule(name: "LLBuildManifest")
        let spmLLBuildModule = self.createSwiftModule(name: "SPMLLBuild")
        let driverSupportModule = self.createSwiftModule(name: "DriverSupport")
        let buildModule = self.createSwiftModule(name: "Build")
        let sourceKitLSPAPIModule = self.createSwiftModule(name: "SourceKitLSPAPI")
        let queryEngineModule = self.createSwiftModule(name: "QueryEngine")
        let sbomModelModule = self.createSwiftModule(name: "SBOMModel")
        let spmSQLite3Module = self.createSwiftModule(name: "SPMSQLite3", type: .systemModule)

        // MARK: - Create Resolved Modules with Dependencies

        let resolvedAsyncFileSystemModule = self.createResolvedModule(
            packageIdentity: identity,
            module: asyncFileSystemModule,
            dependencies: [.product(systemPackageProduct, conditions: [])]
        )

        let resolvedBasicsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: basicsModule,
            dependencies: [
                .module(resolvedAsyncFileSystemModule, conditions: []),
                .product(swiftToolchainCSQLiteProduct, conditions: []),
                .product(dequeModuleProduct, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(swiftToolsSupportAutoProduct, conditions: []),
            ]
        )

        let resolvedBinarySymbolsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: binarySymbolsModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .product(tscBasicProduct, conditions: []),
            ]
        )

        let resolvedPackageModelModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageModelModule,
            dependencies: [.module(resolvedBasicsModule, conditions: [])]
        )

        let resolvedSourceControlModule = self.createResolvedModule(
            packageIdentity: identity,
            module: sourceControlModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
            ]
        )

        let resolvedPackageLoadingModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageLoadingModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
            ]
        )

        let resolvedPackageGraphModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageGraphModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
            ]
        )

        let resolvedPackageCollectionsModelModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageCollectionsModelModule,
            dependencies: [.module(resolvedBasicsModule, conditions: [])]
        )

        let resolvedPackageCollectionsSigningModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageCollectionsSigningModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageCollectionsModelModule, conditions: []),
                .product(cryptoProduct, conditions: []),
                .product(x509Product, conditions: []),
            ]
        )

        let resolvedPackageCollectionsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageCollectionsModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageCollectionsModelModule, conditions: []),
                .module(resolvedPackageCollectionsSigningModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
            ]
        )

        let resolvedPackageMetadataModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageMetadataModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageCollectionsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
            ]
        )

        let resolvedPackageFingerprintModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageFingerprintModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
            ]
        )

        let resolvedPackageSigningModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageSigningModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .product(cryptoProduct, conditions: []),
                .product(x509Product, conditions: []),
            ]
        )

        let resolvedPackageRegistryModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageRegistryModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageFingerprintModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedPackageSigningModule, conditions: []),
            ]
        )

        let resolvedSPMBuildCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: spmBuildCoreModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
            ]
        )

        let resolvedWorkspaceModule = self.createResolvedModule(
            packageIdentity: identity,
            module: workspaceModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageFingerprintModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedPackageRegistryModule, conditions: []),
                .module(resolvedPackageSigningModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
                .module(resolvedSPMBuildCoreModule, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
            ]
        )

        let resolvedLLBuildManifestModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildManifestModule,
            dependencies: [.module(resolvedBasicsModule, conditions: [])]
        )

        let resolvedSPMLLBuildModule = self.createResolvedModule(
            packageIdentity: identity,
            module: spmLLBuildModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .product(llbuildSwiftProduct, conditions: []),
            ]
        )

        let resolvedDriverSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: driverSupportModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .product(swiftDriverProduct, conditions: []),
            ]
        )

        let resolvedBuildModule = self.createResolvedModule(
            packageIdentity: identity,
            module: buildModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedLLBuildManifestModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedSPMBuildCoreModule, conditions: []),
                .module(resolvedSPMLLBuildModule, conditions: []),
                .module(resolvedDriverSupportModule, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
                .product(swiftDriverProduct, conditions: []),
            ]
        )

        let resolvedSourceKitLSPAPIModule = self.createResolvedModule(
            packageIdentity: identity,
            module: sourceKitLSPAPIModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedBuildModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedSPMBuildCoreModule, conditions: []),
            ]
        )

        let resolvedQueryEngineModule = self.createResolvedModule(
            packageIdentity: identity,
            module: queryEngineModule,
            dependencies: [
                .module(resolvedAsyncFileSystemModule, conditions: []),
                .module(resolvedBasicsModule, conditions: []),
                .product(cryptoProduct, conditions: []),
            ]
        )

        let resolvedSBOMModelModule = self.createResolvedModule(
            packageIdentity: identity,
            module: sbomModelModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageCollectionsModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
            ]
        )

        let resolvedSPMSQLite3Module = self.createResolvedModule(
            packageIdentity: identity,
            module: spmSQLite3Module
        )

        return (
            modules: [
                asyncFileSystemModule, basicsModule, binarySymbolsModule, packageModelModule,
                sourceControlModule, packageLoadingModule, packageGraphModule, packageCollectionsModelModule,
                packageCollectionsSigningModule, packageCollectionsModule, packageMetadataModule,
                packageFingerprintModule, packageSigningModule, packageRegistryModule, spmBuildCoreModule,
                workspaceModule, llbuildManifestModule, spmLLBuildModule, driverSupportModule,
                buildModule, sourceKitLSPAPIModule, queryEngineModule, sbomModelModule, spmSQLite3Module,
            ],
            resolvedModules: [
                resolvedAsyncFileSystemModule, resolvedBasicsModule, resolvedBinarySymbolsModule,
                resolvedPackageModelModule, resolvedSourceControlModule, resolvedPackageLoadingModule,
                resolvedPackageGraphModule, resolvedPackageCollectionsModelModule,
                resolvedPackageCollectionsSigningModule,
                resolvedPackageCollectionsModule, resolvedPackageMetadataModule, resolvedPackageFingerprintModule,
                resolvedPackageSigningModule, resolvedPackageRegistryModule, resolvedSPMBuildCoreModule,
                resolvedWorkspaceModule, resolvedLLBuildManifestModule, resolvedSPMLLBuildModule,
                resolvedDriverSupportModule, resolvedBuildModule, resolvedSourceKitLSPAPIModule,
                resolvedQueryEngineModule, resolvedSBOMModelModule, resolvedSPMSQLite3Module,
            ]
        )
    }
}
