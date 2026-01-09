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
    // MARK: - swift-log Package

    static func createSwiftLogPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-log")

        // Modules
        let loggingModule = self.createSwiftModule(name: "Logging")

        // Products
        let loggingProduct = try Product(
            package: identity,
            name: "Logging",
            type: .library(.automatic),
            modules: [loggingModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-log",
            path: "/swift-log",
            modules: [loggingModule],
            products: [loggingProduct]
        )

        // Resolved modules
        let resolvedLoggingModule = self.createResolvedModule(
            packageIdentity: identity,
            module: loggingModule
        )

        // Resolved products
        let resolvedLoggingProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: loggingProduct,
            modules: IdentifiableSet([resolvedLoggingModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedLoggingModule]),
            products: [resolvedLoggingProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-log.git"))
        )

        return (
            package: package,
            modules: [loggingModule],
            products: [loggingProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedLoggingModule],
            resolvedProducts: [resolvedLoggingProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-service-context Package

    static func createSwiftServiceContextPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-service-context")

        // Modules
        let serviceContextModule = self.createSwiftModule(name: "ServiceContextModule")

        // Products
        let serviceContextProduct = try Product(
            package: identity,
            name: "ServiceContextModule",
            type: .library(.automatic),
            modules: [serviceContextModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-service-context",
            path: "/swift-service-context",
            modules: [serviceContextModule],
            products: [serviceContextProduct]
        )

        // Resolved modules
        let resolvedServiceContextModule = self.createResolvedModule(
            packageIdentity: identity,
            module: serviceContextModule
        )

        // Resolved products
        let resolvedServiceContextProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: serviceContextProduct,
            modules: IdentifiableSet([resolvedServiceContextModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedServiceContextModule]),
            products: [resolvedServiceContextProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-service-context.git"))
        )

        return (
            package: package,
            modules: [serviceContextModule],
            products: [serviceContextProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedServiceContextModule],
            resolvedProducts: [resolvedServiceContextProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-distributed-tracing Package

    static func createSwiftDistributedTracingPackage(
        serviceContextProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-distributed-tracing")

        // Modules
        let instrumentationModule = self.createSwiftModule(name: "Instrumentation")
        let tracingModule = self.createSwiftModule(name: "Tracing")

        // Products
        let tracingProduct = try Product(
            package: identity,
            name: "Tracing",
            type: .library(.automatic),
            modules: [tracingModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-distributed-tracing",
            path: "/swift-distributed-tracing",
            modules: [instrumentationModule, tracingModule],
            products: [tracingProduct]
        )

        // Resolved modules
        let resolvedInstrumentationModule = self.createResolvedModule(
            packageIdentity: identity,
            module: instrumentationModule,
            dependencies: [
                .product(serviceContextProduct, conditions: []),
            ]
        )

        let resolvedTracingModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tracingModule,
            dependencies: [
                .module(resolvedInstrumentationModule, conditions: []),
                .product(serviceContextProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedTracingProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: tracingProduct,
            modules: IdentifiableSet([resolvedTracingModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedInstrumentationModule, resolvedTracingModule]),
            products: [resolvedTracingProduct],
            dependencies: [PackageIdentity.plain("swift-service-context")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-distributed-tracing.git"))
        )

        return (
            package: package,
            modules: [instrumentationModule, tracingModule],
            products: [tracingProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedInstrumentationModule, resolvedTracingModule],
            resolvedProducts: [resolvedTracingProduct],
            packageRef: packageRef
        )
    }

    // MARK: - yams Package

    static func createYamsPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("yams")

        // Modules
        let cYamlModule = self.createSwiftModule(name: "CYaml")
        let yamsModule = self.createSwiftModule(name: "Yams")

        // Products
        let yamsProduct = try Product(
            package: identity,
            name: "Yams",
            type: .library(.automatic),
            modules: [yamsModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "Yams",
            path: "/yams",
            modules: [cYamlModule, yamsModule],
            products: [yamsProduct]
        )

        // Resolved modules
        let resolvedCYamlModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cYamlModule
        )

        let resolvedYamsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: yamsModule,
            dependencies: [
                .module(resolvedCYamlModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedYamsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: yamsProduct,
            modules: IdentifiableSet([resolvedYamsModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedCYamlModule, resolvedYamsModule]),
            products: [resolvedYamsProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/jpsim/Yams.git"))
        )

        return (
            package: package,
            modules: [cYamlModule, yamsModule],
            products: [yamsProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedCYamlModule, resolvedYamsModule],
            resolvedProducts: [resolvedYamsProduct],
            packageRef: packageRef
        )
    }

    // MARK: - openapikit Package

    static func createOpenAPIKitPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("openapikit")

        // Modules
        let openAPIKitCoreModule = self.createSwiftModule(name: "OpenAPIKitCore")
        let openAPIKitModule = self.createSwiftModule(name: "OpenAPIKit")
        let openAPIKit30Module = self.createSwiftModule(name: "OpenAPIKit30")
        let openAPIKitCompatModule = self.createSwiftModule(name: "OpenAPIKitCompat")

        // Products
        let openAPIKitProduct = try Product(
            package: identity,
            name: "OpenAPIKit",
            type: .library(.automatic),
            modules: [openAPIKitModule]
        )

        let openAPIKit30Product = try Product(
            package: identity,
            name: "OpenAPIKit30",
            type: .library(.automatic),
            modules: [openAPIKit30Module]
        )

        let openAPIKitCompatProduct = try Product(
            package: identity,
            name: "OpenAPIKitCompat",
            type: .library(.automatic),
            modules: [openAPIKitCompatModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "OpenAPIKit",
            path: "/openapikit",
            modules: [openAPIKitCoreModule, openAPIKitModule, openAPIKit30Module, openAPIKitCompatModule],
            products: [openAPIKitProduct, openAPIKit30Product, openAPIKitCompatProduct]
        )

        // Resolved modules
        let resolvedOpenAPIKitCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIKitCoreModule
        )

        let resolvedOpenAPIKitModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIKitModule,
            dependencies: [
                .module(resolvedOpenAPIKitCoreModule, conditions: []),
            ]
        )

        let resolvedOpenAPIKit30Module = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIKit30Module,
            dependencies: [
                .module(resolvedOpenAPIKitCoreModule, conditions: []),
            ]
        )

        let resolvedOpenAPIKitCompatModule = self.createResolvedModule(
            packageIdentity: identity,
            module: openAPIKitCompatModule,
            dependencies: [
                .module(resolvedOpenAPIKit30Module, conditions: []),
                .module(resolvedOpenAPIKitModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedOpenAPIKitProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: openAPIKitProduct,
            modules: IdentifiableSet([resolvedOpenAPIKitModule])
        )

        let resolvedOpenAPIKit30Product = self.createResolvedProduct(
            packageIdentity: identity,
            product: openAPIKit30Product,
            modules: IdentifiableSet([resolvedOpenAPIKit30Module])
        )

        let resolvedOpenAPIKitCompatProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: openAPIKitCompatProduct,
            modules: IdentifiableSet([resolvedOpenAPIKitCompatModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedOpenAPIKitCoreModule,
                resolvedOpenAPIKitModule,
                resolvedOpenAPIKit30Module,
                resolvedOpenAPIKitCompatModule,
            ]),
            products: [resolvedOpenAPIKitProduct, resolvedOpenAPIKit30Product, resolvedOpenAPIKitCompatProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/mattpolzin/OpenAPIKit"))
        )

        return (
            package: package,
            modules: [openAPIKitCoreModule, openAPIKitModule, openAPIKit30Module, openAPIKitCompatModule],
            products: [openAPIKitProduct, openAPIKit30Product, openAPIKitCompatProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedOpenAPIKitCoreModule,
                resolvedOpenAPIKitModule,
                resolvedOpenAPIKit30Module,
                resolvedOpenAPIKitCompatModule,
            ],
            resolvedProducts: [resolvedOpenAPIKitProduct, resolvedOpenAPIKit30Product, resolvedOpenAPIKitCompatProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-http-types Package

    static func createSwiftHTTPTypesPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-http-types")

        // Modules
        let httpTypesModule = self.createSwiftModule(name: "HTTPTypes")

        // Products
        let httpTypesProduct = try Product(
            package: identity,
            name: "HTTPTypes",
            type: .library(.automatic),
            modules: [httpTypesModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-http-types",
            path: "/swift-http-types",
            modules: [httpTypesModule],
            products: [httpTypesProduct]
        )

        // Resolved modules
        let resolvedHTTPTypesModule = self.createResolvedModule(
            packageIdentity: identity,
            module: httpTypesModule
        )

        // Resolved products
        let resolvedHTTPTypesProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: httpTypesProduct,
            modules: IdentifiableSet([resolvedHTTPTypesModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedHTTPTypesModule]),
            products: [resolvedHTTPTypesProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-http-types.git"))
        )

        return (
            package: package,
            modules: [httpTypesModule],
            products: [httpTypesProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedHTTPTypesModule],
            resolvedProducts: [resolvedHTTPTypesProduct],
            packageRef: packageRef
        )
    }
}
