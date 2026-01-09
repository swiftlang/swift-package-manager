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
    // MARK: - swift-build Package (24 modules, 7 products)

    static func createSPMSwiftBuildPackage(
        swiftSyntaxProduct: ResolvedProduct,
        swiftParserProduct: ResolvedProduct,
        swiftDriverProduct: ResolvedProduct,
        swiftDriverExecutionProduct: ResolvedProduct,
        llbuildSwiftProduct: ResolvedProduct,
        swiftToolsSupportAutoProduct: ResolvedProduct,
        argumentParserProduct: ResolvedProduct,
        systemPackageProduct: ResolvedProduct,
        cryptoProduct: ResolvedProduct,
        x509Product: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-build")

        // MARK: - Create all 24 modules from spm-debug-output.txt

        // Platform modules
        let swbAndroidPlatformModule = self.createSwiftModule(name: "SWBAndroidPlatform")
        let swbApplePlatformModule = self.createSwiftModule(name: "SWBApplePlatform")
        let swbGenericUnixPlatformModule = self.createSwiftModule(name: "SWBGenericUnixPlatform")
        let swbQNXPlatformModule = self.createSwiftModule(name: "SWBQNXPlatform")
        let swbUniversalPlatformModule = self.createSwiftModule(name: "SWBUniversalPlatform")
        let swbWebAssemblyPlatformModule = self.createSwiftModule(name: "SWBWebAssemblyPlatform")
        let swbWindowsPlatformModule = self.createSwiftModule(name: "SWBWindowsPlatform")

        // Core modules
        let swbBuildServiceModule = self.createSwiftModule(name: "SWBBuildService")
        let swbBuildSystemModule = self.createSwiftModule(name: "SWBBuildSystem")
        let swbCASModule = self.createSwiftModule(name: "SWBCAS")
        let swbCLibcModule = self.createSwiftModule(name: "SWBCLibc")
        let swbCSupportModule = self.createSwiftModule(name: "SWBCSupport")
        let swbCoreModule = self.createSwiftModule(name: "SWBCore")
        let swbLLBuildModule = self.createSwiftModule(name: "SWBLLBuild")
        let swbLibcModule = self.createSwiftModule(name: "SWBLibc")
        let swbMacroModule = self.createSwiftModule(name: "SWBMacro")
        let swbProjectModelModule = self.createSwiftModule(name: "SWBProjectModel")
        let swbProtocolModule = self.createSwiftModule(name: "SWBProtocol")
        let swbServiceCoreModule = self.createSwiftModule(name: "SWBServiceCore")
        let swbTaskConstructionModule = self.createSwiftModule(name: "SWBTaskConstruction")
        let swbTaskExecutionModule = self.createSwiftModule(name: "SWBTaskExecution")
        let swbUtilModule = self.createSwiftModule(name: "SWBUtil")

        // SwiftBuild library module
        let swiftBuildLibraryModule = self.createSwiftModule(name: "SwiftBuild")

        // Executable modules
        let swbBuildServiceBundleModule = self.createSwiftModule(name: "SWBBuildServiceBundle", type: .executable)
        let swbuildModule = self.createSwiftModule(name: "swbuild", type: .executable)

        // MARK: - Create products (7 products from spm-debug-output.txt)

        let swbBuildServiceProduct = try Product(
            package: identity,
            name: "SWBBuildService",
            type: .library(.automatic),
            modules: [swbBuildServiceModule]
        )
        let swbBuildServiceBundleProduct = try Product(
            package: identity,
            name: "SWBBuildServiceBundle",
            type: .executable,
            modules: [swbBuildServiceBundleModule]
        )
        let swbProjectModelProduct = try Product(
            package: identity,
            name: "SWBProjectModel",
            type: .library(.automatic),
            modules: [swbProjectModelModule]
        )
        let swbProtocolProduct = try Product(
            package: identity,
            name: "SWBProtocol",
            type: .library(.automatic),
            modules: [swbProtocolModule]
        )
        let swbUtilProduct = try Product(
            package: identity,
            name: "SWBUtil",
            type: .library(.automatic),
            modules: [swbUtilModule]
        )
        let swiftBuildLibraryProduct = try Product(
            package: identity,
            name: "SwiftBuild",
            type: .library(.automatic),
            modules: [swiftBuildLibraryModule]
        )
        let swbuildProduct = try Product(
            package: identity,
            name: "swbuild",
            type: .executable,
            modules: [swbuildModule]
        )

        // MARK: - Create package

        let package = self.createPackage(
            identity: identity,
            displayName: "SwiftBuild",
            path: "/swift-build",
            modules: [
                swbAndroidPlatformModule, swbApplePlatformModule, swbBuildServiceModule,
                swbBuildServiceBundleModule, swbBuildSystemModule, swbCASModule, swbCLibcModule,
                swbCSupportModule, swbCoreModule, swbGenericUnixPlatformModule, swbLLBuildModule,
                swbLibcModule, swbMacroModule, swbProjectModelModule, swbProtocolModule,
                swbQNXPlatformModule, swbServiceCoreModule, swbTaskConstructionModule,
                swbTaskExecutionModule, swbUniversalPlatformModule, swbUtilModule,
                swbWebAssemblyPlatformModule, swbWindowsPlatformModule, swiftBuildLibraryModule,
                swbuildModule,
            ],
            products: [
                swbBuildServiceProduct, swbBuildServiceBundleProduct, swbProjectModelProduct,
                swbProtocolProduct, swbUtilProduct, swiftBuildLibraryProduct, swbuildProduct,
            ]
        )

        // MARK: - Create resolved modules with dependencies (based on spm-debug-output.txt lines 462-586)

        let resolvedSWBCLibcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbCLibcModule,
            dependencies: []
        )

        let resolvedSWBCSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbCSupportModule,
            dependencies: []
        )

        let resolvedSWBLibcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbLibcModule,
            dependencies: [
                .module(resolvedSWBCLibcModule, conditions: []),
            ]
        )

        let resolvedSWBUtilModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbUtilModule,
            dependencies: [
                .module(resolvedSWBCSupportModule, conditions: []),
                .module(resolvedSWBLibcModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
            ]
        )

        let resolvedSWBCASModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbCASModule,
            dependencies: [
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBCSupportModule, conditions: []),
            ]
        )

        let resolvedSWBLLBuildModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbLLBuildModule,
            dependencies: [
                .module(resolvedSWBUtilModule, conditions: []),
                .product(llbuildSwiftProduct, conditions: []),
            ]
        )

        let resolvedSWBProtocolModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbProtocolModule,
            dependencies: [
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBServiceCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbServiceCoreModule,
            dependencies: [
                .module(resolvedSWBProtocolModule, conditions: []),
            ]
        )

        let resolvedSWBMacroModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbMacroModule,
            dependencies: [
                .module(resolvedSWBUtilModule, conditions: []),
                .product(swiftDriverProduct, conditions: []),
            ]
        )

        let resolvedSWBCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbCoreModule,
            dependencies: [
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBProtocolModule, conditions: []),
                .module(resolvedSWBServiceCoreModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBCASModule, conditions: []),
                .module(resolvedSWBLLBuildModule, conditions: []),
                .product(swiftDriverProduct, conditions: []),
            ]
        )

        let resolvedSWBTaskConstructionModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbTaskConstructionModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBTaskExecutionModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbTaskExecutionModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBCASModule, conditions: []),
                .module(resolvedSWBLLBuildModule, conditions: []),
                .module(resolvedSWBTaskConstructionModule, conditions: []),
            ]
        )

        let resolvedSWBBuildSystemModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbBuildSystemModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBTaskConstructionModule, conditions: []),
                .module(resolvedSWBTaskExecutionModule, conditions: []),
            ]
        )

        let resolvedSWBAndroidPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbAndroidPlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBApplePlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbApplePlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBTaskConstructionModule, conditions: []),
            ]
        )

        let resolvedSWBGenericUnixPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbGenericUnixPlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBQNXPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbQNXPlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBUniversalPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbUniversalPlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBTaskConstructionModule, conditions: []),
                .module(resolvedSWBTaskExecutionModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedSWBWebAssemblyPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbWebAssemblyPlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBWindowsPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbWindowsPlatformModule,
            dependencies: [
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBMacroModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
            ]
        )

        let resolvedSWBBuildServiceModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbBuildServiceModule,
            dependencies: [
                .module(resolvedSWBBuildSystemModule, conditions: []),
                .module(resolvedSWBServiceCoreModule, conditions: []),
                .module(resolvedSWBTaskExecutionModule, conditions: []),
                .module(resolvedSWBAndroidPlatformModule, conditions: []),
                .module(resolvedSWBApplePlatformModule, conditions: []),
                .module(resolvedSWBGenericUnixPlatformModule, conditions: []),
                .module(resolvedSWBQNXPlatformModule, conditions: []),
                .module(resolvedSWBUniversalPlatformModule, conditions: []),
                .module(resolvedSWBWebAssemblyPlatformModule, conditions: []),
                .module(resolvedSWBWindowsPlatformModule, conditions: []),
                .product(systemPackageProduct, conditions: []),
            ]
        )

        let resolvedSWBProjectModelModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbProjectModelModule,
            dependencies: [
                .module(resolvedSWBProtocolModule, conditions: []),
            ]
        )

        let resolvedSwiftBuildLibraryModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBuildLibraryModule,
            dependencies: [
                .module(resolvedSWBCSupportModule, conditions: []),
                .module(resolvedSWBCoreModule, conditions: []),
                .module(resolvedSWBProtocolModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBProjectModelModule, conditions: []),
            ]
        )

        let resolvedSWBBuildServiceBundleModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbBuildServiceBundleModule,
            dependencies: [
                .module(resolvedSWBBuildServiceModule, conditions: []),
                .module(resolvedSWBBuildSystemModule, conditions: []),
                .module(resolvedSWBServiceCoreModule, conditions: []),
                .module(resolvedSWBUtilModule, conditions: []),
                .module(resolvedSWBCoreModule, conditions: []),
            ]
        )

        let resolvedSwbuildModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swbuildModule,
            dependencies: [
                .module(resolvedSwiftBuildLibraryModule, conditions: []),
                .module(resolvedSWBBuildServiceBundleModule, conditions: []),
            ]
        )

        // MARK: - Create resolved products

        let resolvedSWBBuildServiceProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swbBuildServiceProduct,
            modules: IdentifiableSet([resolvedSWBBuildServiceModule])
        )

        let resolvedSWBBuildServiceBundleProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swbBuildServiceBundleProduct,
            modules: IdentifiableSet([resolvedSWBBuildServiceBundleModule])
        )

        let resolvedSWBProjectModelProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swbProjectModelProduct,
            modules: IdentifiableSet([resolvedSWBProjectModelModule])
        )

        let resolvedSWBProtocolProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swbProtocolProduct,
            modules: IdentifiableSet([resolvedSWBProtocolModule])
        )

        let resolvedSWBUtilProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swbUtilProduct,
            modules: IdentifiableSet([resolvedSWBUtilModule])
        )

        let resolvedSwiftBuildLibraryProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftBuildLibraryProduct,
            modules: IdentifiableSet([resolvedSwiftBuildLibraryModule])
        )

        let resolvedSwbuildProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swbuildProduct,
            modules: IdentifiableSet([resolvedSwbuildModule])
        )

        // MARK: - Create resolved package

        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedSWBAndroidPlatformModule, resolvedSWBApplePlatformModule, resolvedSWBBuildServiceModule,
                resolvedSWBBuildServiceBundleModule, resolvedSWBBuildSystemModule, resolvedSWBCASModule,
                resolvedSWBCLibcModule, resolvedSWBCSupportModule, resolvedSWBCoreModule,
                resolvedSWBGenericUnixPlatformModule, resolvedSWBLLBuildModule, resolvedSWBLibcModule,
                resolvedSWBMacroModule, resolvedSWBProjectModelModule, resolvedSWBProtocolModule,
                resolvedSWBQNXPlatformModule, resolvedSWBServiceCoreModule, resolvedSWBTaskConstructionModule,
                resolvedSWBTaskExecutionModule, resolvedSWBUniversalPlatformModule, resolvedSWBUtilModule,
                resolvedSWBWebAssemblyPlatformModule, resolvedSWBWindowsPlatformModule,
                resolvedSwiftBuildLibraryModule, resolvedSwbuildModule,
            ]),
            products: [
                resolvedSWBBuildServiceProduct, resolvedSWBBuildServiceBundleProduct,
                resolvedSWBProjectModelProduct, resolvedSWBProtocolProduct, resolvedSWBUtilProduct,
                resolvedSwiftBuildLibraryProduct, resolvedSwbuildProduct,
            ],
            dependencies: [
                PackageIdentity.plain("swift-argument-parser"),
                PackageIdentity.plain("swift-driver"),
                PackageIdentity.plain("swift-llbuild"),
                PackageIdentity.plain("swift-system"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-build.git"))
        )

        return (
            package: package,
            modules: [
                swbAndroidPlatformModule, swbApplePlatformModule, swbBuildServiceModule,
                swbBuildServiceBundleModule, swbBuildSystemModule, swbCASModule, swbCLibcModule,
                swbCSupportModule, swbCoreModule, swbGenericUnixPlatformModule, swbLLBuildModule,
                swbLibcModule, swbMacroModule, swbProjectModelModule, swbProtocolModule,
                swbQNXPlatformModule, swbServiceCoreModule, swbTaskConstructionModule,
                swbTaskExecutionModule, swbUniversalPlatformModule, swbUtilModule,
                swbWebAssemblyPlatformModule, swbWindowsPlatformModule, swiftBuildLibraryModule,
                swbuildModule,
            ],
            products: [
                swbBuildServiceProduct, swbBuildServiceBundleProduct, swbProjectModelProduct,
                swbProtocolProduct, swbUtilProduct, swiftBuildLibraryProduct, swbuildProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedSWBAndroidPlatformModule, resolvedSWBApplePlatformModule, resolvedSWBBuildServiceModule,
                resolvedSWBBuildServiceBundleModule, resolvedSWBBuildSystemModule, resolvedSWBCASModule,
                resolvedSWBCLibcModule, resolvedSWBCSupportModule, resolvedSWBCoreModule,
                resolvedSWBGenericUnixPlatformModule, resolvedSWBLLBuildModule, resolvedSWBLibcModule,
                resolvedSWBMacroModule, resolvedSWBProjectModelModule, resolvedSWBProtocolModule,
                resolvedSWBQNXPlatformModule, resolvedSWBServiceCoreModule, resolvedSWBTaskConstructionModule,
                resolvedSWBTaskExecutionModule, resolvedSWBUniversalPlatformModule, resolvedSWBUtilModule,
                resolvedSWBWebAssemblyPlatformModule, resolvedSWBWindowsPlatformModule,
                resolvedSwiftBuildLibraryModule, resolvedSwbuildModule,
            ],
            resolvedProducts: [
                resolvedSWBBuildServiceProduct, resolvedSWBBuildServiceBundleProduct,
                resolvedSWBProjectModelProduct, resolvedSWBProtocolProduct, resolvedSWBUtilProduct,
                resolvedSwiftBuildLibraryProduct, resolvedSwbuildProduct,
            ],
            packageRef: packageRef
        )
    }
}
