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
    // MARK: - swiftly Package (Root)

    static func createSwiftlyRootPackage(
        rootPath: String = "/tmp/swiftly-mock",
        openAPIGeneratorProduct: ResolvedProduct,
        openAPIRuntimeProduct: ResolvedProduct,
        argumentParserProduct: ResolvedProduct,
        systemPackageProduct: ResolvedProduct,
        asyncHTTPClientProduct: ResolvedProduct,
        nioFoundationCompatProduct: ResolvedProduct,
        openAPIAsyncHTTPClientProduct: ResolvedProduct,
        subprocessProduct: ResolvedProduct,
        swiftToolsSupportProduct: ResolvedProduct,
        nioFileSystemProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swiftly")

        // System module
        let cLibArchiveModule = self.createSwiftModule(name: "CLibArchive", type: .systemModule)

        // Plugin modules
        let generateCommandModelsModule = self.createSwiftModule(name: "GenerateCommandModels", type: .plugin)
        let generateDocsReferenceModule = self.createSwiftModule(name: "GenerateDocsReference", type: .plugin)

        // Executable modules
        let generateCommandModelsExecModule = self.createSwiftModule(name: "generate-command-models", type: .executable)
        let generateDocsReferenceExecModule = self.createSwiftModule(name: "generate-docs-reference", type: .executable)
        let swiftlyModule = self.createSwiftModule(name: "Swiftly", type: .executable)
        let testSwiftlyModule = self.createSwiftModule(name: "TestSwiftly", type: .executable)
        let buildSwiftlyReleaseModule = self.createSwiftModule(name: "build-swiftly-release", type: .executable)

        // Library modules
        let swiftlyWebsiteAPIModule = self.createSwiftModule(name: "SwiftlyWebsiteAPI")
        let swiftlyDownloadAPIModule = self.createSwiftModule(name: "SwiftlyDownloadAPI")
        let swiftlyDocsModule = self.createSwiftModule(name: "SwiftlyDocs")
        let swiftlyCoreModule = self.createSwiftModule(name: "SwiftlyCore")
        let macOSPlatformModule = self.createSwiftModule(name: "MacOSPlatform")
        let linuxPlatformModule = self.createSwiftModule(name: "LinuxPlatform")

        // Test module
        let swiftlyTestsModule = self.createSwiftModule(name: "SwiftlyTests", type: .test)

        // Products
        let swiftlyProduct = try Product(
            package: identity,
            name: "swiftly",
            type: .executable,
            modules: [swiftlyModule]
        )

        let testSwiftlyProduct = try Product(
            package: identity,
            name: "test-swiftly",
            type: .executable,
            modules: [testSwiftlyModule]
        )

        let generateDocsReferenceProduct = try Product(
            package: identity,
            name: "generate-docs-reference",
            type: .executable,
            modules: [generateDocsReferenceExecModule]
        )

        let generateCommandModelsProduct = try Product(
            package: identity,
            name: "generate-command-models",
            type: .executable,
            modules: [generateCommandModelsExecModule]
        )

        let buildSwiftlyReleaseProduct = try Product(
            package: identity,
            name: "build-swiftly-release",
            type: .executable,
            modules: [buildSwiftlyReleaseModule]
        )

        let swiftlyTestsProduct = try Product(
            package: identity,
            name: "SwiftlyTests",
            type: .test,
            modules: [swiftlyTestsModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swiftly",
            path: rootPath,
            modules: [
                cLibArchiveModule, generateCommandModelsModule, generateDocsReferenceModule,
                generateCommandModelsExecModule, generateDocsReferenceExecModule,
                swiftlyModule, testSwiftlyModule, buildSwiftlyReleaseModule,
                swiftlyWebsiteAPIModule, swiftlyDownloadAPIModule, swiftlyDocsModule,
                swiftlyCoreModule, macOSPlatformModule, linuxPlatformModule,
                swiftlyTestsModule,
            ],
            products: [
                swiftlyProduct, testSwiftlyProduct, generateDocsReferenceProduct,
                generateCommandModelsProduct, buildSwiftlyReleaseProduct, swiftlyTestsProduct,
            ]
        )

        // Resolved modules - System and plugins
        let resolvedCLibArchiveModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cLibArchiveModule
        )

        let resolvedGenerateCommandModelsExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateCommandModelsExecModule,
            dependencies: [
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
            ]
        )

        let resolvedGenerateCommandModelsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateCommandModelsModule,
            dependencies: [
                .module(resolvedGenerateCommandModelsExecModule, conditions: []),
            ]
        )

        let resolvedGenerateDocsReferenceExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateDocsReferenceExecModule,
            dependencies: [
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedGenerateDocsReferenceModule = self.createResolvedModule(
            packageIdentity: identity,
            module: generateDocsReferenceModule,
            dependencies: [
                .module(resolvedGenerateDocsReferenceExecModule, conditions: []),
            ]
        )

        // Resolved library modules
        let resolvedSwiftlyWebsiteAPIModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftlyWebsiteAPIModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
            ]
        )

        let resolvedSwiftlyDownloadAPIModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftlyDownloadAPIModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
            ]
        )

        let resolvedSwiftlyDocsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftlyDocsModule
        )

        let resolvedSwiftlyCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftlyCoreModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .module(resolvedSwiftlyDownloadAPIModule, conditions: []),
                .module(resolvedSwiftlyWebsiteAPIModule, conditions: []),
                .module(resolvedGenerateCommandModelsModule, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(openAPIAsyncHTTPClientProduct, conditions: []),
                .product(subprocessProduct, conditions: []),
            ]
        )

        let resolvedMacOSPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: macOSPlatformModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .module(resolvedSwiftlyDownloadAPIModule, conditions: []),
                .module(resolvedSwiftlyWebsiteAPIModule, conditions: []),
                .module(resolvedGenerateCommandModelsModule, conditions: []),
                .module(resolvedSwiftlyCoreModule, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(openAPIAsyncHTTPClientProduct, conditions: []),
                .product(subprocessProduct, conditions: []),
            ]
        )

        let resolvedLinuxPlatformModule = self.createResolvedModule(
            packageIdentity: identity,
            module: linuxPlatformModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .module(resolvedSwiftlyDownloadAPIModule, conditions: []),
                .module(resolvedSwiftlyWebsiteAPIModule, conditions: []),
                .module(resolvedGenerateCommandModelsModule, conditions: []),
                .module(resolvedSwiftlyCoreModule, conditions: []),
                .module(resolvedCLibArchiveModule, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(openAPIAsyncHTTPClientProduct, conditions: []),
                .product(subprocessProduct, conditions: []),
            ]
        )

        // Resolved executable modules
        let resolvedSwiftlyModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftlyModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .module(resolvedSwiftlyDownloadAPIModule, conditions: []),
                .module(resolvedSwiftlyWebsiteAPIModule, conditions: []),
                .module(resolvedGenerateCommandModelsModule, conditions: []),
                .module(resolvedSwiftlyCoreModule, conditions: []),
                .module(resolvedCLibArchiveModule, conditions: []),
                .module(resolvedMacOSPlatformModule, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(openAPIAsyncHTTPClientProduct, conditions: []),
                .product(subprocessProduct, conditions: []),
                .product(swiftToolsSupportProduct, conditions: []),
            ]
        )

        let resolvedTestSwiftlyModule = self.createResolvedModule(
            packageIdentity: identity,
            module: testSwiftlyModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .module(resolvedSwiftlyDownloadAPIModule, conditions: []),
                .module(resolvedSwiftlyWebsiteAPIModule, conditions: []),
                .module(resolvedGenerateCommandModelsModule, conditions: []),
                .module(resolvedSwiftlyCoreModule, conditions: []),
                .module(resolvedCLibArchiveModule, conditions: []),
                .module(resolvedMacOSPlatformModule, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(openAPIAsyncHTTPClientProduct, conditions: []),
                .product(subprocessProduct, conditions: []),
            ]
        )

        let resolvedBuildSwiftlyReleaseModule = self.createResolvedModule(
            packageIdentity: identity,
            module: buildSwiftlyReleaseModule,
            dependencies: [
                .product(openAPIGeneratorProduct, conditions: []),
                .module(resolvedSwiftlyDownloadAPIModule, conditions: []),
                .module(resolvedSwiftlyWebsiteAPIModule, conditions: []),
                .module(resolvedGenerateCommandModelsModule, conditions: []),
                .module(resolvedSwiftlyCoreModule, conditions: []),
                .module(resolvedCLibArchiveModule, conditions: []),
                .module(resolvedMacOSPlatformModule, conditions: []),
                .product(openAPIRuntimeProduct, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(openAPIAsyncHTTPClientProduct, conditions: []),
                .product(subprocessProduct, conditions: []),
                .product(nioFileSystemProduct, conditions: []),
            ]
        )

        let resolvedSwiftlyTestsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftlyTestsModule,
            dependencies: [
                .product(systemPackageProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedSwiftlyProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftlyProduct,
            modules: IdentifiableSet([resolvedSwiftlyModule])
        )

        let resolvedTestSwiftlyProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: testSwiftlyProduct,
            modules: IdentifiableSet([resolvedTestSwiftlyModule])
        )

        let resolvedGenerateDocsReferenceProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: generateDocsReferenceProduct,
            modules: IdentifiableSet([resolvedGenerateDocsReferenceExecModule])
        )

        let resolvedGenerateCommandModelsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: generateCommandModelsProduct,
            modules: IdentifiableSet([resolvedGenerateCommandModelsExecModule])
        )

        let resolvedBuildSwiftlyReleaseProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: buildSwiftlyReleaseProduct,
            modules: IdentifiableSet([resolvedBuildSwiftlyReleaseModule])
        )

        let resolvedSwiftlyTestsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftlyTestsProduct,
            modules: IdentifiableSet([resolvedSwiftlyTestsModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedCLibArchiveModule, resolvedGenerateCommandModelsModule, resolvedGenerateDocsReferenceModule,
                resolvedGenerateCommandModelsExecModule, resolvedGenerateDocsReferenceExecModule,
                resolvedSwiftlyModule, resolvedTestSwiftlyModule, resolvedBuildSwiftlyReleaseModule,
                resolvedSwiftlyWebsiteAPIModule, resolvedSwiftlyDownloadAPIModule, resolvedSwiftlyDocsModule,
                resolvedSwiftlyCoreModule, resolvedMacOSPlatformModule, resolvedLinuxPlatformModule,
                resolvedSwiftlyTestsModule,
            ]),
            products: [
                resolvedSwiftlyProduct, resolvedTestSwiftlyProduct, resolvedGenerateDocsReferenceProduct,
                resolvedGenerateCommandModelsProduct, resolvedBuildSwiftlyReleaseProduct, resolvedSwiftlyTestsProduct,
            ],
            dependencies: [
                PackageIdentity.plain("async-http-client"),
                PackageIdentity.plain("swift-argument-parser"),
                PackageIdentity.plain("swift-docc-plugin"),
                PackageIdentity.plain("swift-nio"),
                PackageIdentity.plain("swift-openapi-async-http-client"),
                PackageIdentity.plain("swift-openapi-generator"),
                PackageIdentity.plain("swift-openapi-runtime"),
                PackageIdentity.plain("swift-subprocess"),
                PackageIdentity.plain("swift-system"),
                PackageIdentity.plain("swift-tools-support-core"),
                PackageIdentity.plain("swiftformat"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .root(AbsolutePath(rootPath))
        )

        return (
            package: package,
            modules: [
                cLibArchiveModule, generateCommandModelsModule, generateDocsReferenceModule,
                generateCommandModelsExecModule, generateDocsReferenceExecModule,
                swiftlyModule, testSwiftlyModule, buildSwiftlyReleaseModule,
                swiftlyWebsiteAPIModule, swiftlyDownloadAPIModule, swiftlyDocsModule,
                swiftlyCoreModule, macOSPlatformModule, linuxPlatformModule,
                swiftlyTestsModule,
            ],
            products: [
                swiftlyProduct, testSwiftlyProduct, generateDocsReferenceProduct,
                generateCommandModelsProduct, buildSwiftlyReleaseProduct, swiftlyTestsProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedCLibArchiveModule, resolvedGenerateCommandModelsModule, resolvedGenerateDocsReferenceModule,
                resolvedGenerateCommandModelsExecModule, resolvedGenerateDocsReferenceExecModule,
                resolvedSwiftlyModule, resolvedTestSwiftlyModule, resolvedBuildSwiftlyReleaseModule,
                resolvedSwiftlyWebsiteAPIModule, resolvedSwiftlyDownloadAPIModule, resolvedSwiftlyDocsModule,
                resolvedSwiftlyCoreModule, resolvedMacOSPlatformModule, resolvedLinuxPlatformModule,
                resolvedSwiftlyTestsModule,
            ],
            resolvedProducts: [
                resolvedSwiftlyProduct, resolvedTestSwiftlyProduct, resolvedGenerateDocsReferenceProduct,
                resolvedGenerateCommandModelsProduct, resolvedBuildSwiftlyReleaseProduct, resolvedSwiftlyTestsProduct,
            ],
            packageRef: packageRef
        )
    }
}
