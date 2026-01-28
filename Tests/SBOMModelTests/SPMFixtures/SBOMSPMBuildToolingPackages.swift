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
    // MARK: - swift-llbuild Package

    static func createSPMSwiftLLBuildPackage(
        swiftToolchainCSQLiteProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-llbuild")

        // Modules
        let llvmDemangleModule = self.createSwiftModule(name: "llvmDemangle")
        let llvmSupportModule = self.createSwiftModule(name: "llvmSupport")
        let llbuildBasicModule = self.createSwiftModule(name: "llbuildBasic")
        let llbuildCoreModule = self.createSwiftModule(name: "llbuildCore")
        let llbuildNinjaModule = self.createSwiftModule(name: "llbuildNinja")
        let llbuildBuildSystemModule = self.createSwiftModule(name: "llbuildBuildSystem")
        let llbuildCommandsModule = self.createSwiftModule(name: "llbuildCommands")
        let libllbuildModule = self.createSwiftModule(name: "libllbuild")
        let llbuildSwiftModule = self.createSwiftModule(name: "llbuildSwift")
        let llbuildAnalysisModule = self.createSwiftModule(name: "llbuildAnalysis")
        let llbuildExecModule = self.createSwiftModule(name: "llbuild", type: .executable)

        // Products
        let libllbuildProduct = try Product(
            package: identity,
            name: "libllbuild",
            type: .library(.automatic),
            modules: [libllbuildModule]
        )

        let llbuildProduct = try Product(
            package: identity,
            name: "llbuild",
            type: .executable,
            modules: [llbuildExecModule]
        )

        let llbuildAnalysisProduct = try Product(
            package: identity,
            name: "llbuildAnalysis",
            type: .library(.automatic),
            modules: [llbuildAnalysisModule]
        )

        let llbuildSwiftProduct = try Product(
            package: identity,
            name: "llbuildSwift",
            type: .library(.automatic),
            modules: [llbuildSwiftModule]
        )

        let llbuildSwiftDynamicProduct = try Product(
            package: identity,
            name: "llbuildSwiftDynamic",
            type: .library(.dynamic),
            modules: [llbuildSwiftModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "llbuild",
            path: "/swift-llbuild",
            modules: [
                llvmDemangleModule, llvmSupportModule, llbuildBasicModule, llbuildCoreModule,
                llbuildNinjaModule, llbuildBuildSystemModule, llbuildCommandsModule,
                libllbuildModule, llbuildSwiftModule, llbuildAnalysisModule, llbuildExecModule,
            ],
            products: [
                libllbuildProduct, llbuildProduct, llbuildAnalysisProduct,
                llbuildSwiftProduct, llbuildSwiftDynamicProduct,
            ]
        )

        // Resolved modules
        let resolvedLLVMDemangleModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llvmDemangleModule
        )

        let resolvedLLVMSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llvmSupportModule,
            dependencies: [
                .module(resolvedLLVMDemangleModule, conditions: []),
            ]
        )

        let resolvedLLBuildBasicModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildBasicModule,
            dependencies: [
                .module(resolvedLLVMSupportModule, conditions: []),
            ]
        )

        let resolvedLLBuildCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildCoreModule,
            dependencies: [
                .module(resolvedLLBuildBasicModule, conditions: []),
                .product(swiftToolchainCSQLiteProduct, conditions: []),
            ]
        )

        let resolvedLLBuildNinjaModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildNinjaModule,
            dependencies: [
                .module(resolvedLLBuildBasicModule, conditions: []),
            ]
        )

        let resolvedLLBuildBuildSystemModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildBuildSystemModule,
            dependencies: [
                .module(resolvedLLBuildCoreModule, conditions: []),
            ]
        )

        let resolvedLLBuildCommandsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildCommandsModule,
            dependencies: [
                .module(resolvedLLBuildCoreModule, conditions: []),
                .module(resolvedLLBuildBuildSystemModule, conditions: []),
                .module(resolvedLLBuildNinjaModule, conditions: []),
            ]
        )

        let resolvedLibllbuildModule = self.createResolvedModule(
            packageIdentity: identity,
            module: libllbuildModule,
            dependencies: [
                .module(resolvedLLBuildCoreModule, conditions: []),
                .module(resolvedLLBuildBuildSystemModule, conditions: []),
                .module(resolvedLLBuildNinjaModule, conditions: []),
            ]
        )

        let resolvedLLBuildSwiftModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildSwiftModule,
            dependencies: [
                .module(resolvedLibllbuildModule, conditions: []),
            ]
        )

        let resolvedLLBuildAnalysisModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildAnalysisModule,
            dependencies: [
                .module(resolvedLLBuildSwiftModule, conditions: []),
            ]
        )

        let resolvedLLBuildExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: llbuildExecModule,
            dependencies: [
                .module(resolvedLLBuildCommandsModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedLibllbuildProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: libllbuildProduct,
            modules: IdentifiableSet([resolvedLibllbuildModule])
        )

        let resolvedLLBuildProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: llbuildProduct,
            modules: IdentifiableSet([resolvedLLBuildExecModule])
        )

        let resolvedLLBuildAnalysisProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: llbuildAnalysisProduct,
            modules: IdentifiableSet([resolvedLLBuildAnalysisModule])
        )

        let resolvedLLBuildSwiftProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: llbuildSwiftProduct,
            modules: IdentifiableSet([resolvedLLBuildSwiftModule])
        )

        let resolvedLLBuildSwiftDynamicProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: llbuildSwiftDynamicProduct,
            modules: IdentifiableSet([resolvedLLBuildSwiftModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedLLVMDemangleModule, resolvedLLVMSupportModule, resolvedLLBuildBasicModule,
                resolvedLLBuildCoreModule, resolvedLLBuildNinjaModule, resolvedLLBuildBuildSystemModule,
                resolvedLLBuildCommandsModule, resolvedLibllbuildModule, resolvedLLBuildSwiftModule,
                resolvedLLBuildAnalysisModule, resolvedLLBuildExecModule,
            ]),
            products: [
                resolvedLibllbuildProduct, resolvedLLBuildProduct, resolvedLLBuildAnalysisProduct,
                resolvedLLBuildSwiftProduct, resolvedLLBuildSwiftDynamicProduct,
            ],
            dependencies: [PackageIdentity.plain("swift-toolchain-sqlite")],
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-llbuild.git"))
        )

        return (
            package: package,
            modules: [
                llvmDemangleModule, llvmSupportModule, llbuildBasicModule, llbuildCoreModule,
                llbuildNinjaModule, llbuildBuildSystemModule, llbuildCommandsModule,
                libllbuildModule, llbuildSwiftModule, llbuildAnalysisModule, llbuildExecModule,
            ],
            products: [
                libllbuildProduct, llbuildProduct, llbuildAnalysisProduct,
                llbuildSwiftProduct, llbuildSwiftDynamicProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedLLVMDemangleModule, resolvedLLVMSupportModule, resolvedLLBuildBasicModule,
                resolvedLLBuildCoreModule, resolvedLLBuildNinjaModule, resolvedLLBuildBuildSystemModule,
                resolvedLLBuildCommandsModule, resolvedLibllbuildModule, resolvedLLBuildSwiftModule,
                resolvedLLBuildAnalysisModule, resolvedLLBuildExecModule,
            ],
            resolvedProducts: [
                resolvedLibllbuildProduct, resolvedLLBuildProduct, resolvedLLBuildAnalysisProduct,
                resolvedLLBuildSwiftProduct, resolvedLLBuildSwiftDynamicProduct,
            ],
            packageRef: packageRef
        )
    }

    // MARK: - swift-tools-support-core Package

    static func createSPMSwiftToolsSupportCorePackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-tools-support-core")

        // Modules
        let tscLibcModule = self.createSwiftModule(name: "TSCLibc")
        let tscClibcModule = self.createSwiftModule(name: "TSCclibc")
        let tscBasicModule = self.createSwiftModule(name: "TSCBasic")
        let tscUtilityModule = self.createSwiftModule(name: "TSCUtility")
        let tscTestSupportModule = self.createSwiftModule(name: "TSCTestSupport")

        // Products
        let tscBasicProduct = try Product(
            package: identity,
            name: "TSCBasic",
            type: .library(.automatic),
            modules: [tscBasicModule]
        )

        let swiftToolsSupportProduct = try Product(
            package: identity,
            name: "SwiftToolsSupport",
            type: .library(.dynamic),
            modules: [tscBasicModule, tscUtilityModule]
        )

        let swiftToolsSupportAutoProduct = try Product(
            package: identity,
            name: "SwiftToolsSupport-auto",
            type: .library(.automatic),
            modules: [tscBasicModule, tscUtilityModule]
        )

        let tscTestSupportProduct = try Product(
            package: identity,
            name: "TSCTestSupport",
            type: .library(.automatic),
            modules: [tscTestSupportModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-tools-support-core",
            path: "/swift-tools-support-core",
            modules: [tscLibcModule, tscClibcModule, tscBasicModule, tscUtilityModule, tscTestSupportModule],
            products: [tscBasicProduct, swiftToolsSupportProduct, swiftToolsSupportAutoProduct, tscTestSupportProduct]
        )

        // Resolved modules
        let resolvedTSCLibcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscLibcModule
        )

        let resolvedTSCClibcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscClibcModule
        )

        let resolvedTSCBasicModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscBasicModule,
            dependencies: [
                .module(resolvedTSCLibcModule, conditions: []),
                .module(resolvedTSCClibcModule, conditions: []),
            ]
        )

        let resolvedTSCUtilityModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscUtilityModule,
            dependencies: [
                .module(resolvedTSCBasicModule, conditions: []),
                .module(resolvedTSCClibcModule, conditions: []),
            ]
        )

        let resolvedTSCTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscTestSupportModule,
            dependencies: [
                .module(resolvedTSCBasicModule, conditions: []),
                .module(resolvedTSCUtilityModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedTSCBasicProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: tscBasicProduct,
            modules: IdentifiableSet([resolvedTSCBasicModule])
        )

        let resolvedSwiftToolsSupportProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftToolsSupportProduct,
            modules: IdentifiableSet([resolvedTSCBasicModule, resolvedTSCUtilityModule])
        )

        let resolvedSwiftToolsSupportAutoProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftToolsSupportAutoProduct,
            modules: IdentifiableSet([resolvedTSCBasicModule, resolvedTSCUtilityModule])
        )

        let resolvedTSCTestSupportProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: tscTestSupportProduct,
            modules: IdentifiableSet([resolvedTSCTestSupportModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedTSCLibcModule, resolvedTSCClibcModule, resolvedTSCBasicModule,
                resolvedTSCUtilityModule, resolvedTSCTestSupportModule,
            ]),
            products: [
                resolvedTSCBasicProduct, resolvedSwiftToolsSupportProduct,
                resolvedSwiftToolsSupportAutoProduct, resolvedTSCTestSupportProduct,
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-tools-support-core.git"))
        )

        return (
            package: package,
            modules: [tscLibcModule, tscClibcModule, tscBasicModule, tscUtilityModule, tscTestSupportModule],
            products: [tscBasicProduct, swiftToolsSupportProduct, swiftToolsSupportAutoProduct, tscTestSupportProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedTSCLibcModule, resolvedTSCClibcModule, resolvedTSCBasicModule,
                resolvedTSCUtilityModule, resolvedTSCTestSupportModule,
            ],
            resolvedProducts: [
                resolvedTSCBasicProduct, resolvedSwiftToolsSupportProduct,
                resolvedSwiftToolsSupportAutoProduct, resolvedTSCTestSupportProduct,
            ],
            packageRef: packageRef
        )
    }

    // MARK: - swift-driver Package

    static func createSPMSwiftDriverPackage(
        swiftToolsSupportAutoProduct: ResolvedProduct,
        llbuildSwiftProduct: ResolvedProduct,
        argumentParserProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-driver")

        // Modules
        let cSwiftScanModule = self.createSwiftModule(name: "CSwiftScan")
        let swiftOptionsModule = self.createSwiftModule(name: "SwiftOptions")
        let swiftDriverModule = self.createSwiftModule(name: "SwiftDriver")
        let swiftDriverExecutionModule = self.createSwiftModule(name: "SwiftDriverExecution")
        let swiftDriverExecModule = self.createSwiftModule(name: "swift-driver", type: .executable)
        let swiftHelpModule = self.createSwiftModule(name: "swift-help", type: .executable)
        let swiftBuildSDKInterfacesModule = self.createSwiftModule(
            name: "swift-build-sdk-interfaces",
            type: .executable
        )

        // Products
        let swiftDriverProduct = try Product(
            package: identity,
            name: "SwiftDriver",
            type: .library(.automatic),
            modules: [swiftDriverModule]
        )

        let swiftDriverDynamicProduct = try Product(
            package: identity,
            name: "SwiftDriverDynamic",
            type: .library(.dynamic),
            modules: [swiftDriverModule]
        )

        let swiftDriverExecutionProduct = try Product(
            package: identity,
            name: "SwiftDriverExecution",
            type: .library(.automatic),
            modules: [swiftDriverExecutionModule]
        )

        let swiftOptionsProduct = try Product(
            package: identity,
            name: "SwiftOptions",
            type: .library(.automatic),
            modules: [swiftOptionsModule]
        )

        let swiftDriverExecProduct = try Product(
            package: identity,
            name: "swift-driver",
            type: .executable,
            modules: [swiftDriverExecModule]
        )

        let swiftHelpProduct = try Product(
            package: identity,
            name: "swift-help",
            type: .executable,
            modules: [swiftHelpModule]
        )

        let swiftBuildSDKInterfacesProduct = try Product(
            package: identity,
            name: "swift-build-sdk-interfaces",
            type: .executable,
            modules: [swiftBuildSDKInterfacesModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-driver",
            path: "/swift-driver",
            modules: [
                cSwiftScanModule, swiftOptionsModule, swiftDriverModule, swiftDriverExecutionModule,
                swiftDriverExecModule, swiftHelpModule, swiftBuildSDKInterfacesModule,
            ],
            products: [
                swiftDriverProduct, swiftDriverDynamicProduct, swiftDriverExecutionProduct,
                swiftOptionsProduct, swiftDriverExecProduct, swiftHelpProduct, swiftBuildSDKInterfacesProduct,
            ]
        )

        // Resolved modules
        let resolvedCSwiftScanModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cSwiftScanModule
        )

        let resolvedSwiftOptionsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftOptionsModule,
            dependencies: [
                .product(swiftToolsSupportAutoProduct, conditions: []),
            ]
        )

        let resolvedSwiftDriverModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftDriverModule,
            dependencies: [
                .module(resolvedSwiftOptionsModule, conditions: []),
                .module(resolvedCSwiftScanModule, conditions: []),
                .product(swiftToolsSupportAutoProduct, conditions: []),
            ]
        )

        let resolvedSwiftDriverExecutionModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftDriverExecutionModule,
            dependencies: [
                .module(resolvedSwiftDriverModule, conditions: []),
                .product(swiftToolsSupportAutoProduct, conditions: []),
                .product(llbuildSwiftProduct, conditions: []),
            ]
        )

        let resolvedSwiftDriverExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftDriverExecModule,
            dependencies: [
                .module(resolvedSwiftDriverExecutionModule, conditions: []),
                .module(resolvedSwiftDriverModule, conditions: []),
            ]
        )

        let resolvedSwiftHelpModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftHelpModule,
            dependencies: [
                .module(resolvedSwiftOptionsModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(swiftToolsSupportAutoProduct, conditions: []),
            ]
        )

        let resolvedSwiftBuildSDKInterfacesModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBuildSDKInterfacesModule,
            dependencies: [
                .module(resolvedSwiftDriverModule, conditions: []),
                .module(resolvedSwiftDriverExecutionModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedSwiftDriverProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDriverProduct,
            modules: IdentifiableSet([resolvedSwiftDriverModule])
        )

        let resolvedSwiftDriverDynamicProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDriverDynamicProduct,
            modules: IdentifiableSet([resolvedSwiftDriverModule])
        )

        let resolvedSwiftDriverExecutionProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDriverExecutionProduct,
            modules: IdentifiableSet([resolvedSwiftDriverExecutionModule])
        )

        let resolvedSwiftOptionsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftOptionsProduct,
            modules: IdentifiableSet([resolvedSwiftOptionsModule])
        )

        let resolvedSwiftDriverExecProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDriverExecProduct,
            modules: IdentifiableSet([resolvedSwiftDriverExecModule])
        )

        let resolvedSwiftHelpProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftHelpProduct,
            modules: IdentifiableSet([resolvedSwiftHelpModule])
        )

        let resolvedSwiftBuildSDKInterfacesProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftBuildSDKInterfacesProduct,
            modules: IdentifiableSet([resolvedSwiftBuildSDKInterfacesModule])
        )

        // Resolved package
        // swift-driver
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedCSwiftScanModule, resolvedSwiftOptionsModule, resolvedSwiftDriverModule,
                resolvedSwiftDriverExecutionModule, resolvedSwiftDriverExecModule, resolvedSwiftHelpModule,
                resolvedSwiftBuildSDKInterfacesModule,
            ]),
            products: [
                resolvedSwiftDriverProduct, resolvedSwiftDriverDynamicProduct, resolvedSwiftDriverExecutionProduct,
                resolvedSwiftOptionsProduct, resolvedSwiftDriverExecProduct, resolvedSwiftHelpProduct,
                resolvedSwiftBuildSDKInterfacesProduct,
            ],
            dependencies: [
                PackageIdentity.plain("swift-argument-parser"),
                PackageIdentity.plain("swift-llbuild"),
                PackageIdentity.plain("swift-tools-support-core"),
            ],
            // enabledTraits: ["SPMTrait1", "SPMTrait2"]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-driver.git"))
        )

        return (
            package: package,
            modules: [
                cSwiftScanModule, swiftOptionsModule, swiftDriverModule, swiftDriverExecutionModule,
                swiftDriverExecModule, swiftHelpModule, swiftBuildSDKInterfacesModule,
            ],
            products: [
                swiftDriverProduct, swiftDriverDynamicProduct, swiftDriverExecutionProduct,
                swiftOptionsProduct, swiftDriverExecProduct, swiftHelpProduct, swiftBuildSDKInterfacesProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedCSwiftScanModule, resolvedSwiftOptionsModule, resolvedSwiftDriverModule,
                resolvedSwiftDriverExecutionModule, resolvedSwiftDriverExecModule, resolvedSwiftHelpModule,
                resolvedSwiftBuildSDKInterfacesModule,
            ],
            resolvedProducts: [
                resolvedSwiftDriverProduct, resolvedSwiftDriverDynamicProduct, resolvedSwiftDriverExecutionProduct,
                resolvedSwiftOptionsProduct, resolvedSwiftDriverExecProduct, resolvedSwiftHelpProduct,
                resolvedSwiftBuildSDKInterfacesProduct,
            ],
            packageRef: packageRef
        )
    }
}
