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

    static func createSwiftSystemPackage() throws -> (
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
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-system"))
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

    // MARK: - swift-subprocess Package

    static func createSwiftSubprocessPackage(
        systemPackageProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-subprocess")

        // Modules
        let subprocessCShimsModule = self.createSwiftModule(name: "_SubprocessCShims")
        let subprocessModule = self.createSwiftModule(name: "Subprocess")

        // Products
        let subprocessProduct = try Product(
            package: identity,
            name: "Subprocess",
            type: .library(.automatic),
            modules: [subprocessModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "Subprocess",
            path: "/swift-subprocess",
            modules: [subprocessCShimsModule, subprocessModule],
            products: [subprocessProduct]
        )

        // Resolved modules
        let resolvedSubprocessCShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: subprocessCShimsModule
        )

        let resolvedSubprocessModule = self.createResolvedModule(
            packageIdentity: identity,
            module: subprocessModule,
            dependencies: [
                .module(resolvedSubprocessCShimsModule, conditions: []),
                .product(systemPackageProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedSubprocessProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: subprocessProduct,
            modules: IdentifiableSet([resolvedSubprocessModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedSubprocessCShimsModule, resolvedSubprocessModule]),
            products: [resolvedSubprocessProduct],
            dependencies: [PackageIdentity.plain("swift-system")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-subprocess"))
        )

        return (
            package: package,
            modules: [subprocessCShimsModule, subprocessModule],
            products: [subprocessProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedSubprocessCShimsModule, resolvedSubprocessModule],
            resolvedProducts: [resolvedSubprocessProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-argument-parser Package

    static func createSwiftArgumentParserPackage() throws -> (
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

        // Products
        let argumentParserProduct = try Product(
            package: identity,
            name: "ArgumentParser",
            type: .library(.automatic),
            modules: [argumentParserModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-argument-parser",
            path: "/swift-argument-parser",
            modules: [argumentParserToolInfoModule, argumentParserModule],
            products: [argumentParserProduct]
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

        // Resolved products
        let resolvedArgumentParserProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: argumentParserProduct,
            modules: IdentifiableSet([resolvedArgumentParserModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedArgumentParserToolInfoModule, resolvedArgumentParserModule]),
            products: [resolvedArgumentParserProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-argument-parser"))
        )

        return (
            package: package,
            modules: [argumentParserToolInfoModule, argumentParserModule],
            products: [argumentParserProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedArgumentParserToolInfoModule, resolvedArgumentParserModule],
            resolvedProducts: [resolvedArgumentParserProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-tools-support-core Package

    static func createSwiftToolsSupportCorePackage() throws -> (
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
        let tscClibcModule = self.createSwiftModule(name: "TSCclibc")
        let tscLibcModule = self.createSwiftModule(name: "TSCLibc")
        let tscBasicModule = self.createSwiftModule(name: "TSCBasic")
        let tscUtilityModule = self.createSwiftModule(name: "TSCUtility")

        // Products
        let swiftToolsSupportAutoProduct = try Product(
            package: identity,
            name: "SwiftToolsSupport-auto",
            type: .library(.automatic),
            modules: [tscBasicModule, tscUtilityModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-tools-support-core",
            path: "/swift-tools-support-core",
            modules: [tscClibcModule, tscLibcModule, tscBasicModule, tscUtilityModule],
            products: [swiftToolsSupportAutoProduct]
        )

        // Resolved modules
        let resolvedTSCClibcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscClibcModule
        )

        let resolvedTSCLibcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tscLibcModule
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

        // Resolved products
        let resolvedSwiftToolsSupportAutoProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftToolsSupportAutoProduct,
            modules: IdentifiableSet([resolvedTSCBasicModule, resolvedTSCUtilityModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedTSCClibcModule,
                resolvedTSCLibcModule,
                resolvedTSCBasicModule,
                resolvedTSCUtilityModule,
            ]),
            products: [resolvedSwiftToolsSupportAutoProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-tools-support-core.git"))
        )

        return (
            package: package,
            modules: [tscClibcModule, tscLibcModule, tscBasicModule, tscUtilityModule],
            products: [swiftToolsSupportAutoProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedTSCClibcModule,
                resolvedTSCLibcModule,
                resolvedTSCBasicModule,
                resolvedTSCUtilityModule,
            ],
            resolvedProducts: [resolvedSwiftToolsSupportAutoProduct],
            packageRef: packageRef
        )
    }
}
