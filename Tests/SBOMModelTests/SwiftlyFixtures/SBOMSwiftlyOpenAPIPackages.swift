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
    // MARK: - swift-openapi-runtime Package

    static func createSwiftOpenAPIRuntimePackage(
        httpTypesProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-openapi-runtime")

        // Modules
        let openAPIRuntimeModule = self.createSwiftModule(name: "OpenAPIRuntime")

        // Products
        let openAPIRuntimeProduct = try Product(
            package: identity,
            name: "OpenAPIRuntime",
            type: .library(.automatic),
            modules: [openAPIRuntimeModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-openapi-runtime",
            path: "/swift-openapi-runtime",
            modules: [openAPIRuntimeModule],
            products: [openAPIRuntimeProduct]
        )

        // Resolved modules
        let resolvedOpenAPIRuntimeModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIRuntimeModule,
            dependencies: [
                .product(httpTypesProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedOpenAPIRuntimeProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: openAPIRuntimeProduct,
            modules: IdentifiableSet([resolvedOpenAPIRuntimeModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedOpenAPIRuntimeModule]),
            products: [resolvedOpenAPIRuntimeProduct],
            dependencies: [PackageIdentity.plain("swift-http-types")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-openapi-runtime"))
        )

        return (
            package: package,
            modules: [openAPIRuntimeModule],
            products: [openAPIRuntimeProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedOpenAPIRuntimeModule],
            resolvedProducts: [resolvedOpenAPIRuntimeProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-openapi-generator Package

    static func createSwiftOpenAPIGeneratorPackage(
        openAPIKitProduct: ResolvedProduct,
        openAPIKit30Product: ResolvedProduct,
        openAPIKitCompatProduct: ResolvedProduct,
        algorithmsProduct: ResolvedProduct,
        orderedCollectionsProduct: ResolvedProduct,
        yamsProduct: ResolvedProduct,
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
        let identity = PackageIdentity.plain("swift-openapi-generator")

        // Modules
        let openAPIGeneratorCoreModule = self.createSwiftModule(name: "_OpenAPIGeneratorCore")
        let openAPIGeneratorModule = self.createSwiftModule(name: "OpenAPIGenerator", type: .plugin)
        let swiftOpenAPIGeneratorModule = self.createSwiftModule(name: "swift-openapi-generator", type: .executable)

        // Products
        let openAPIGeneratorProduct = try Product(
            package: identity,
            name: "OpenAPIGenerator",
            type: .plugin,
            modules: [openAPIGeneratorModule]
        )

        let swiftOpenAPIGeneratorProduct = try Product(
            package: identity,
            name: "swift-openapi-generator",
            type: .executable,
            modules: [swiftOpenAPIGeneratorModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-openapi-generator",
            path: "/swift-openapi-generator",
            modules: [openAPIGeneratorCoreModule, openAPIGeneratorModule, swiftOpenAPIGeneratorModule],
            products: [openAPIGeneratorProduct, swiftOpenAPIGeneratorProduct]
        )

        // Resolved modules
        let resolvedOpenAPIGeneratorCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIGeneratorCoreModule,
            dependencies: [
                .product(openAPIKitProduct, conditions: []),
                .product(openAPIKit30Product, conditions: []),
                .product(openAPIKitCompatProduct, conditions: []),
                .product(algorithmsProduct, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
                .product(yamsProduct, conditions: []),
            ]
        )

        let resolvedSwiftOpenAPIGeneratorModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftOpenAPIGeneratorModule,
            dependencies: [
                .module(resolvedOpenAPIGeneratorCoreModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedOpenAPIGeneratorModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIGeneratorModule,
            dependencies: [
                .module(resolvedSwiftOpenAPIGeneratorModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedOpenAPIGeneratorProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: openAPIGeneratorProduct,
            modules: IdentifiableSet([resolvedOpenAPIGeneratorModule])
        )

        let resolvedSwiftOpenAPIGeneratorProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftOpenAPIGeneratorProduct,
            modules: IdentifiableSet([resolvedSwiftOpenAPIGeneratorModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedOpenAPIGeneratorCoreModule,
                resolvedOpenAPIGeneratorModule,
                resolvedSwiftOpenAPIGeneratorModule,
            ]),
            products: [resolvedOpenAPIGeneratorProduct, resolvedSwiftOpenAPIGeneratorProduct],
            dependencies: [
                PackageIdentity.plain("openapikit"),
                PackageIdentity.plain("swift-algorithms"),
                PackageIdentity.plain("swift-argument-parser"),
                PackageIdentity.plain("swift-collections"),
                PackageIdentity.plain("yams"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-openapi-generator"))
        )

        return (
            package: package,
            modules: [openAPIGeneratorCoreModule, openAPIGeneratorModule, swiftOpenAPIGeneratorModule],
            products: [openAPIGeneratorProduct, swiftOpenAPIGeneratorProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedOpenAPIGeneratorCoreModule,
                resolvedOpenAPIGeneratorModule,
                resolvedSwiftOpenAPIGeneratorModule,
            ],
            resolvedProducts: [resolvedOpenAPIGeneratorProduct, resolvedSwiftOpenAPIGeneratorProduct],
            packageRef: packageRef
        )
    }

    // MARK: - async-http-client Package

    static func createAsyncHTTPClientPackage(
        nioProduct: ResolvedProduct,
        nioTLSProduct: ResolvedProduct,
        nioCoreProduct: ResolvedProduct,
        nioPosixProduct: ResolvedProduct,
        nioHTTP1Product: ResolvedProduct,
        nioConcurrencyHelpersProduct: ResolvedProduct,
        nioHTTP2Product: ResolvedProduct,
        nioSSLProduct: ResolvedProduct,
        nioHTTPCompressionProduct: ResolvedProduct,
        nioSOCKSProduct: ResolvedProduct,
        nioTransportServicesProduct: ResolvedProduct,
        atomicsProduct: ResolvedProduct,
        algorithmsProduct: ResolvedProduct,
        loggingProduct: ResolvedProduct,
        tracingProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("async-http-client")

        // Modules
        let cAsyncHTTPClientModule = self.createSwiftModule(name: "CAsyncHTTPClient")
        let asyncHTTPClientModule = self.createSwiftModule(name: "AsyncHTTPClient")

        // Products
        let asyncHTTPClientProduct = try Product(
            package: identity,
            name: "AsyncHTTPClient",
            type: .library(.automatic),
            modules: [asyncHTTPClientModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "async-http-client",
            path: "/async-http-client",
            modules: [cAsyncHTTPClientModule, asyncHTTPClientModule],
            products: [asyncHTTPClientProduct]
        )

        // Resolved modules
        let resolvedCAsyncHTTPClientModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cAsyncHTTPClientModule
        )

        let resolvedAsyncHTTPClientModule = self.createResolvedModule(
            packageIdentity: identity,
            module: asyncHTTPClientModule,
            dependencies: [
                .module(resolvedCAsyncHTTPClientModule, conditions: []),
                .product(nioProduct, conditions: []),
                .product(nioTLSProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
                .product(nioPosixProduct, conditions: []),
                .product(nioHTTP1Product, conditions: []),
                .product(nioConcurrencyHelpersProduct, conditions: []),
                .product(nioHTTP2Product, conditions: []),
                .product(nioSSLProduct, conditions: []),
                .product(nioHTTPCompressionProduct, conditions: []),
                .product(nioSOCKSProduct, conditions: []),
                .product(nioTransportServicesProduct, conditions: []),
                .product(atomicsProduct, conditions: []),
                .product(algorithmsProduct, conditions: []),
                .product(loggingProduct, conditions: []),
                .product(tracingProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedAsyncHTTPClientProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: asyncHTTPClientProduct,
            modules: IdentifiableSet([resolvedAsyncHTTPClientModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedCAsyncHTTPClientModule, resolvedAsyncHTTPClientModule]),
            products: [resolvedAsyncHTTPClientProduct],
            dependencies: [
                PackageIdentity.plain("swift-algorithms"),
                PackageIdentity.plain("swift-atomics"),
                PackageIdentity.plain("swift-distributed-tracing"),
                PackageIdentity.plain("swift-log"),
                PackageIdentity.plain("swift-nio"),
                PackageIdentity.plain("swift-nio-extras"),
                PackageIdentity.plain("swift-nio-http2"),
                PackageIdentity.plain("swift-nio-ssl"),
                PackageIdentity.plain("swift-nio-transport-services"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swift-server/async-http-client"))
        )

        return (
            package: package,
            modules: [cAsyncHTTPClientModule, asyncHTTPClientModule],
            products: [asyncHTTPClientProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedCAsyncHTTPClientModule, resolvedAsyncHTTPClientModule],
            resolvedProducts: [resolvedAsyncHTTPClientProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-openapi-async-http-client Package

    static func createSwiftOpenAPIAsyncHTTPClientPackage(
        openAPIRuntimeProduct: ResolvedProduct,
        httpTypesProduct: ResolvedProduct,
        asyncHTTPClientProduct: ResolvedProduct,
        nioFoundationCompatProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-openapi-async-http-client")

        // Modules
        let openAPIAsyncHTTPClientModule = self.createSwiftModule(name: "OpenAPIAsyncHTTPClient")

        // Products
        let openAPIAsyncHTTPClientProduct = try Product(
            package: identity,
            name: "OpenAPIAsyncHTTPClient",
            type: .library(.automatic),
            modules: [openAPIAsyncHTTPClientModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-openapi-async-http-client",
            path: "/swift-openapi-async-http-client",
            modules: [openAPIAsyncHTTPClientModule],
            products: [openAPIAsyncHTTPClientProduct]
        )

        // Resolved modules
        let resolvedOpenAPIAsyncHTTPClientModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIAsyncHTTPClientModule,
            dependencies: [
                .product(openAPIRuntimeProduct, conditions: []),
                .product(httpTypesProduct, conditions: []),
                .product(asyncHTTPClientProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedOpenAPIAsyncHTTPClientProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: openAPIAsyncHTTPClientProduct,
            modules: IdentifiableSet([resolvedOpenAPIAsyncHTTPClientModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedOpenAPIAsyncHTTPClientModule]),
            products: [resolvedOpenAPIAsyncHTTPClientProduct],
            dependencies: [
                PackageIdentity.plain("async-http-client"),
                PackageIdentity.plain("swift-http-types"),
                PackageIdentity.plain("swift-nio"),
                PackageIdentity.plain("swift-openapi-runtime"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(
                SourceControlURL("https://github.com/swift-server/swift-openapi-async-http-client")
            )
        )

        return (
            package: package,
            modules: [openAPIAsyncHTTPClientModule],
            products: [openAPIAsyncHTTPClientProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedOpenAPIAsyncHTTPClientModule],
            resolvedProducts: [resolvedOpenAPIAsyncHTTPClientProduct],
            packageRef: packageRef
        )
    }
}
