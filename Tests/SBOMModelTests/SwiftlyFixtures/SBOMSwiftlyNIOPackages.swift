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
    // MARK: - swift-nio Package (Core)

    static func createSwiftNIOPackage(
        atomicsProduct: ResolvedProduct,
        dequeProduct: ResolvedProduct,
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
        let identity = PackageIdentity.plain("swift-nio")

        // C modules
        let cnioAtomicsModule = self.createSwiftModule(name: "CNIOAtomics")
        let cnioDarwinModule = self.createSwiftModule(name: "CNIODarwin")
        let cnioLinuxModule = self.createSwiftModule(name: "CNIOLinux")
        let cnioWindowsModule = self.createSwiftModule(name: "CNIOWindows")
        let cnioWASIModule = self.createSwiftModule(name: "CNIOWASI")
        let cnioPosixModule = self.createSwiftModule(name: "CNIOPosix")
        let cnioLLHTTPModule = self.createSwiftModule(name: "CNIOLLHTTP")

        // Internal modules
        let nioBase64Module = self.createSwiftModule(name: "_NIOBase64")
        let nioDataStructuresModule = self.createSwiftModule(name: "_NIODataStructures")
        let nioFileSystemModule = self.createSwiftModule(name: "_NIOFileSystem")

        // Core modules
        let nioConcurrencyHelpersModule = self.createSwiftModule(name: "NIOConcurrencyHelpers")
        let nioCoreModule = self.createSwiftModule(name: "NIOCore")
        let nioEmbeddedModule = self.createSwiftModule(name: "NIOEmbedded")
        let nioPosixModule = self.createSwiftModule(name: "NIOPosix")
        let nioModule = self.createSwiftModule(name: "NIO")
        let nioTLSModule = self.createSwiftModule(name: "NIOTLS")
        let nioHTTP1Module = self.createSwiftModule(name: "NIOHTTP1")
        let nioFoundationCompatModule = self.createSwiftModule(name: "NIOFoundationCompat")
        let nioFileSystemPublicModule = self.createSwiftModule(name: "NIOFileSystem")

        // Products
        let nioConcurrencyHelpersProduct = try Product(
            package: identity,
            name: "NIOConcurrencyHelpers",
            type: .library(.automatic),
            modules: [nioConcurrencyHelpersModule]
        )

        let nioCoreProduct = try Product(
            package: identity,
            name: "NIOCore",
            type: .library(.automatic),
            modules: [nioCoreModule]
        )

        let nioProduct = try Product(
            package: identity,
            name: "NIO",
            type: .library(.automatic),
            modules: [nioModule]
        )

        let nioPosixProduct = try Product(
            package: identity,
            name: "NIOPosix",
            type: .library(.automatic),
            modules: [nioPosixModule]
        )

        let nioTLSProduct = try Product(
            package: identity,
            name: "NIOTLS",
            type: .library(.automatic),
            modules: [nioTLSModule]
        )

        let nioHTTP1Product = try Product(
            package: identity,
            name: "NIOHTTP1",
            type: .library(.automatic),
            modules: [nioHTTP1Module]
        )

        let nioFoundationCompatProduct = try Product(
            package: identity,
            name: "NIOFoundationCompat",
            type: .library(.automatic),
            modules: [nioFoundationCompatModule]
        )

        let nioFileSystemProduct = try Product(
            package: identity,
            name: "_NIOFileSystem",
            type: .library(.automatic),
            modules: [nioFileSystemPublicModule, nioFileSystemModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-nio",
            path: "/swift-nio",
            modules: [
                cnioAtomicsModule, cnioDarwinModule, cnioLinuxModule, cnioWindowsModule,
                cnioWASIModule, cnioPosixModule, cnioLLHTTPModule,
                nioBase64Module, nioDataStructuresModule, nioFileSystemModule,
                nioConcurrencyHelpersModule, nioCoreModule, nioEmbeddedModule,
                nioPosixModule, nioModule, nioTLSModule, nioHTTP1Module,
                nioFoundationCompatModule, nioFileSystemPublicModule,
            ],
            products: [
                nioConcurrencyHelpersProduct, nioCoreProduct, nioProduct,
                nioPosixProduct, nioTLSProduct, nioHTTP1Product,
                nioFoundationCompatProduct, nioFileSystemProduct,
            ]
        )

        // Resolved C modules
        let resolvedCNIOAtomicsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioAtomicsModule
        )

        let resolvedCNIODarwinModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioDarwinModule
        )

        let resolvedCNIOLinuxModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioLinuxModule
        )

        let resolvedCNIOWindowsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioWindowsModule
        )

        let resolvedCNIOWASIModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioWASIModule
        )

        let resolvedCNIOPosixModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioPosixModule
        )

        let resolvedCNIOLLHTTPModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioLLHTTPModule
        )

        // Resolved internal modules
        let resolvedNIOBase64Module = self.createResolvedModule(
            packageIdentity: identity,
            module: nioBase64Module
        )

        let resolvedNIODataStructuresModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioDataStructuresModule
        )

        // Resolved core modules
        let resolvedNIOConcurrencyHelpersModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioConcurrencyHelpersModule,
            dependencies: [
                .module(resolvedCNIOAtomicsModule, conditions: []),
            ]
        )

        let resolvedNIOCoreModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioCoreModule,
            dependencies: [
                .module(resolvedCNIOAtomicsModule, conditions: []),
                .module(resolvedNIOConcurrencyHelpersModule, conditions: []),
                .module(resolvedNIOBase64Module, conditions: []),
                .module(resolvedCNIODarwinModule, conditions: []),
                .module(resolvedCNIOLinuxModule, conditions: []),
                .module(resolvedCNIOWindowsModule, conditions: []),
                .module(resolvedCNIOWASIModule, conditions: []),
                .module(resolvedNIODataStructuresModule, conditions: []),
                .product(dequeProduct, conditions: []),
                .product(atomicsProduct, conditions: []),
            ]
        )

        let resolvedNIOEmbeddedModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioEmbeddedModule,
            dependencies: [
                .module(resolvedNIOCoreModule, conditions: []),
                .module(resolvedNIOConcurrencyHelpersModule, conditions: []),
                .module(resolvedNIODataStructuresModule, conditions: []),
                .product(atomicsProduct, conditions: []),
                .product(dequeProduct, conditions: []),
            ]
        )

        let resolvedNIOPosixModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioPosixModule,
            dependencies: [
                .module(resolvedCNIOLinuxModule, conditions: []),
                .module(resolvedCNIODarwinModule, conditions: []),
                .module(resolvedCNIOWindowsModule, conditions: []),
                .module(resolvedNIOConcurrencyHelpersModule, conditions: []),
                .module(resolvedNIOCoreModule, conditions: []),
                .module(resolvedNIODataStructuresModule, conditions: []),
                .module(resolvedCNIOPosixModule, conditions: []),
                .product(atomicsProduct, conditions: []),
            ]
        )

        let resolvedNIOModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioModule,
            dependencies: [
                .module(resolvedNIOCoreModule, conditions: []),
                .module(resolvedNIOEmbeddedModule, conditions: []),
                .module(resolvedNIOPosixModule, conditions: []),
            ]
        )

        let resolvedNIOTLSModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioTLSModule,
            dependencies: [
                .module(resolvedNIOModule, conditions: []),
                .module(resolvedNIOCoreModule, conditions: []),
                .product(dequeProduct, conditions: []),
            ]
        )

        let resolvedNIOHTTP1Module = self.createResolvedModule(
            packageIdentity: identity,
            module: nioHTTP1Module,
            dependencies: [
                .module(resolvedNIOModule, conditions: []),
                .module(resolvedNIOCoreModule, conditions: []),
                .module(resolvedNIOConcurrencyHelpersModule, conditions: []),
                .module(resolvedCNIOLLHTTPModule, conditions: []),
                .product(dequeProduct, conditions: []),
            ]
        )

        let resolvedNIOFoundationCompatModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioFoundationCompatModule,
            dependencies: [
                .module(resolvedNIOModule, conditions: []),
                .module(resolvedNIOCoreModule, conditions: []),
            ]
        )

        let resolvedNIOFileSystemModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioFileSystemModule,
            dependencies: [
                .module(resolvedNIOCoreModule, conditions: []),
                .module(resolvedNIOPosixModule, conditions: []),
                .module(resolvedCNIOLinuxModule, conditions: []),
                .module(resolvedCNIODarwinModule, conditions: []),
                .product(atomicsProduct, conditions: []),
                .product(dequeProduct, conditions: []),
                .product(systemPackageProduct, conditions: []),
            ]
        )

        let resolvedNIOFileSystemPublicModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioFileSystemPublicModule,
            dependencies: [
                .module(resolvedNIOFileSystemModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedNIOConcurrencyHelpersProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioConcurrencyHelpersProduct,
            modules: IdentifiableSet([resolvedNIOConcurrencyHelpersModule])
        )

        let resolvedNIOCoreProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioCoreProduct,
            modules: IdentifiableSet([resolvedNIOCoreModule])
        )

        let resolvedNIOProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioProduct,
            modules: IdentifiableSet([resolvedNIOModule])
        )

        let resolvedNIOPosixProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioPosixProduct,
            modules: IdentifiableSet([resolvedNIOPosixModule])
        )

        let resolvedNIOTLSProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioTLSProduct,
            modules: IdentifiableSet([resolvedNIOTLSModule])
        )

        let resolvedNIOHTTP1Product = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioHTTP1Product,
            modules: IdentifiableSet([resolvedNIOHTTP1Module])
        )

        let resolvedNIOFoundationCompatProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioFoundationCompatProduct,
            modules: IdentifiableSet([resolvedNIOFoundationCompatModule])
        )

        let resolvedNIOFileSystemProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioFileSystemProduct,
            modules: IdentifiableSet([resolvedNIOFileSystemPublicModule, resolvedNIOFileSystemModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedCNIOAtomicsModule, resolvedCNIODarwinModule, resolvedCNIOLinuxModule,
                resolvedCNIOWindowsModule, resolvedCNIOWASIModule, resolvedCNIOPosixModule,
                resolvedCNIOLLHTTPModule, resolvedNIOBase64Module, resolvedNIODataStructuresModule,
                resolvedNIOConcurrencyHelpersModule, resolvedNIOCoreModule, resolvedNIOEmbeddedModule,
                resolvedNIOPosixModule, resolvedNIOModule, resolvedNIOTLSModule, resolvedNIOHTTP1Module,
                resolvedNIOFoundationCompatModule, resolvedNIOFileSystemModule, resolvedNIOFileSystemPublicModule,
            ]),
            products: [
                resolvedNIOConcurrencyHelpersProduct, resolvedNIOCoreProduct, resolvedNIOProduct,
                resolvedNIOPosixProduct, resolvedNIOTLSProduct, resolvedNIOHTTP1Product,
                resolvedNIOFoundationCompatProduct, resolvedNIOFileSystemProduct,
            ],
            dependencies: [
                PackageIdentity.plain("swift-atomics"),
                PackageIdentity.plain("swift-collections"),
                PackageIdentity.plain("swift-system"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-nio.git"))
        )

        return (
            package: package,
            modules: [
                cnioAtomicsModule, cnioDarwinModule, cnioLinuxModule, cnioWindowsModule,
                cnioWASIModule, cnioPosixModule, cnioLLHTTPModule,
                nioBase64Module, nioDataStructuresModule, nioFileSystemModule,
                nioConcurrencyHelpersModule, nioCoreModule, nioEmbeddedModule,
                nioPosixModule, nioModule, nioTLSModule, nioHTTP1Module,
                nioFoundationCompatModule, nioFileSystemPublicModule,
            ],
            products: [
                nioConcurrencyHelpersProduct, nioCoreProduct, nioProduct,
                nioPosixProduct, nioTLSProduct, nioHTTP1Product,
                nioFoundationCompatProduct, nioFileSystemProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedCNIOAtomicsModule, resolvedCNIODarwinModule, resolvedCNIOLinuxModule,
                resolvedCNIOWindowsModule, resolvedCNIOWASIModule, resolvedCNIOPosixModule,
                resolvedCNIOLLHTTPModule, resolvedNIOBase64Module, resolvedNIODataStructuresModule,
                resolvedNIOConcurrencyHelpersModule, resolvedNIOCoreModule, resolvedNIOEmbeddedModule,
                resolvedNIOPosixModule, resolvedNIOModule, resolvedNIOTLSModule, resolvedNIOHTTP1Module,
                resolvedNIOFoundationCompatModule, resolvedNIOFileSystemModule, resolvedNIOFileSystemPublicModule,
            ],
            resolvedProducts: [
                resolvedNIOConcurrencyHelpersProduct, resolvedNIOCoreProduct, resolvedNIOProduct,
                resolvedNIOPosixProduct, resolvedNIOTLSProduct, resolvedNIOHTTP1Product,
                resolvedNIOFoundationCompatProduct, resolvedNIOFileSystemProduct,
            ],
            packageRef: packageRef
        )
    }

    // MARK: - swift-nio-ssl Package

    static func createSwiftNIOSSLPackage(
        nioProduct: ResolvedProduct,
        nioCoreProduct: ResolvedProduct,
        nioConcurrencyHelpersProduct: ResolvedProduct,
        nioTLSProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-nio-ssl")

        // Modules
        let cnioBoringSSLModule = self.createSwiftModule(name: "CNIOBoringSSL")
        let cnioBoringSSLShimsModule = self.createSwiftModule(name: "CNIOBoringSSLShims")
        let nioSSLModule = self.createSwiftModule(name: "NIOSSL")

        // Products
        let nioSSLProduct = try Product(
            package: identity,
            name: "NIOSSL",
            type: .library(.automatic),
            modules: [nioSSLModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-nio-ssl",
            path: "/swift-nio-ssl",
            modules: [cnioBoringSSLModule, cnioBoringSSLShimsModule, nioSSLModule],
            products: [nioSSLProduct]
        )

        // Resolved modules
        let resolvedCNIOBoringSSLModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioBoringSSLModule
        )

        let resolvedCNIOBoringSSLShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioBoringSSLShimsModule,
            dependencies: [
                .module(resolvedCNIOBoringSSLModule, conditions: []),
            ]
        )

        let resolvedNIOSSLModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioSSLModule,
            dependencies: [
                .module(resolvedCNIOBoringSSLModule, conditions: []),
                .module(resolvedCNIOBoringSSLShimsModule, conditions: []),
                .product(nioProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
                .product(nioConcurrencyHelpersProduct, conditions: []),
                .product(nioTLSProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedNIOSSLProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioSSLProduct,
            modules: IdentifiableSet([resolvedNIOSSLModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedCNIOBoringSSLModule,
                resolvedCNIOBoringSSLShimsModule,
                resolvedNIOSSLModule,
            ]),
            products: [resolvedNIOSSLProduct],
            dependencies: [PackageIdentity.plain("swift-nio")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-nio-ssl.git"))
        )

        return (
            package: package,
            modules: [cnioBoringSSLModule, cnioBoringSSLShimsModule, nioSSLModule],
            products: [nioSSLProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedCNIOBoringSSLModule,
                resolvedCNIOBoringSSLShimsModule,
                resolvedNIOSSLModule,
            ],
            resolvedProducts: [resolvedNIOSSLProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-nio-http2 Package

    static func createSwiftNIOHTTP2Package(
        nioProduct: ResolvedProduct,
        nioCoreProduct: ResolvedProduct,
        nioConcurrencyHelpersProduct: ResolvedProduct,
        nioHTTP1Product: ResolvedProduct,
        nioTLSProduct: ResolvedProduct,
        atomicsProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-nio-http2")

        // Modules
        let niohpackModule = self.createSwiftModule(name: "NIOHPACK")
        let niohttp2Module = self.createSwiftModule(name: "NIOHTTP2")

        // Products
        let niohttp2Product = try Product(
            package: identity,
            name: "NIOHTTP2",
            type: .library(.automatic),
            modules: [niohttp2Module]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-nio-http2",
            path: "/swift-nio-http2",
            modules: [niohpackModule, niohttp2Module],
            products: [niohttp2Product]
        )

        // Resolved modules
        let resolvedNIOHPACKModule = self.createResolvedModule(
            packageIdentity: identity,
            module: niohpackModule,
            dependencies: [
                .product(nioProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
                .product(nioConcurrencyHelpersProduct, conditions: []),
                .product(nioHTTP1Product, conditions: []),
            ]
        )

        let resolvedNIOHTTP2Module = self.createResolvedModule(
            packageIdentity: identity,
            module: niohttp2Module,
            dependencies: [
                .module(resolvedNIOHPACKModule, conditions: []),
                .product(nioProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
                .product(nioHTTP1Product, conditions: []),
                .product(nioTLSProduct, conditions: []),
                .product(nioConcurrencyHelpersProduct, conditions: []),
                .product(atomicsProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedNIOHTTP2Product = self.createResolvedProduct(
            packageIdentity: identity,
            product: niohttp2Product,
            modules: IdentifiableSet([resolvedNIOHTTP2Module])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedNIOHPACKModule, resolvedNIOHTTP2Module]),
            products: [resolvedNIOHTTP2Product],
            dependencies: [
                PackageIdentity.plain("swift-atomics"),
                PackageIdentity.plain("swift-nio"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-nio-http2.git"))
        )

        return (
            package: package,
            modules: [niohpackModule, niohttp2Module],
            products: [niohttp2Product],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedNIOHPACKModule, resolvedNIOHTTP2Module],
            resolvedProducts: [resolvedNIOHTTP2Product],
            packageRef: packageRef
        )
    }

    // MARK: - swift-nio-extras Package

    static func createSwiftNIOExtrasPackage(
        nioProduct: ResolvedProduct,
        nioCoreProduct: ResolvedProduct,
        nioHTTP1Product: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-nio-extras")

        // Modules
        let cnioExtrasZlibModule = self.createSwiftModule(name: "CNIOExtrasZlib")
        let nioHTTPCompressionModule = self.createSwiftModule(name: "NIOHTTPCompression")
        let nioSOCKSModule = self.createSwiftModule(name: "NIOSOCKS")

        // Products
        let nioHTTPCompressionProduct = try Product(
            package: identity,
            name: "NIOHTTPCompression",
            type: .library(.automatic),
            modules: [nioHTTPCompressionModule]
        )

        let nioSOCKSProduct = try Product(
            package: identity,
            name: "NIOSOCKS",
            type: .library(.automatic),
            modules: [nioSOCKSModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-nio-extras",
            path: "/swift-nio-extras",
            modules: [cnioExtrasZlibModule, nioHTTPCompressionModule, nioSOCKSModule],
            products: [nioHTTPCompressionProduct, nioSOCKSProduct]
        )

        // Resolved modules
        let resolvedCNIOExtrasZlibModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cnioExtrasZlibModule
        )

        let resolvedNIOHTTPCompressionModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioHTTPCompressionModule,
            dependencies: [
                .module(resolvedCNIOExtrasZlibModule, conditions: []),
                .product(nioProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
                .product(nioHTTP1Product, conditions: []),
            ]
        )

        let resolvedNIOSOCKSModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioSOCKSModule,
            dependencies: [
                .product(nioProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedNIOHTTPCompressionProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioHTTPCompressionProduct,
            modules: IdentifiableSet([resolvedNIOHTTPCompressionModule])
        )

        let resolvedNIOSOCKSProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioSOCKSProduct,
            modules: IdentifiableSet([resolvedNIOSOCKSModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedCNIOExtrasZlibModule,
                resolvedNIOHTTPCompressionModule,
                resolvedNIOSOCKSModule,
            ]),
            products: [resolvedNIOHTTPCompressionProduct, resolvedNIOSOCKSProduct],
            dependencies: [PackageIdentity.plain("swift-nio")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-nio-extras.git"))
        )

        return (
            package: package,
            modules: [cnioExtrasZlibModule, nioHTTPCompressionModule, nioSOCKSModule],
            products: [nioHTTPCompressionProduct, nioSOCKSProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedCNIOExtrasZlibModule,
                resolvedNIOHTTPCompressionModule,
                resolvedNIOSOCKSModule,
            ],
            resolvedProducts: [resolvedNIOHTTPCompressionProduct, resolvedNIOSOCKSProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-nio-transport-services Package

    static func createSwiftNIOTransportServicesPackage(
        nioProduct: ResolvedProduct,
        nioCoreProduct: ResolvedProduct,
        nioFoundationCompatProduct: ResolvedProduct,
        nioTLSProduct: ResolvedProduct,
        atomicsProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-nio-transport-services")

        // Modules
        let nioTransportServicesModule = self.createSwiftModule(name: "NIOTransportServices")

        // Products
        let nioTransportServicesProduct = try Product(
            package: identity,
            name: "NIOTransportServices",
            type: .library(.automatic),
            modules: [nioTransportServicesModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-nio-transport-services",
            path: "/swift-nio-transport-services",
            modules: [nioTransportServicesModule],
            products: [nioTransportServicesProduct]
        )

        // Resolved modules
        let resolvedNIOTransportServicesModule = self.createResolvedModule(
            packageIdentity: identity,
            module: nioTransportServicesModule,
            dependencies: [
                .product(nioProduct, conditions: []),
                .product(nioCoreProduct, conditions: []),
                .product(nioFoundationCompatProduct, conditions: []),
                .product(nioTLSProduct, conditions: []),
                .product(atomicsProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedNIOTransportServicesProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: nioTransportServicesProduct,
            modules: IdentifiableSet([resolvedNIOTransportServicesModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedNIOTransportServicesModule]),
            products: [resolvedNIOTransportServicesProduct],
            dependencies: [
                PackageIdentity.plain("swift-atomics"),
                PackageIdentity.plain("swift-nio"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-nio-transport-services.git"))
        )

        return (
            package: package,
            modules: [nioTransportServicesModule],
            products: [nioTransportServicesProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedNIOTransportServicesModule],
            resolvedProducts: [resolvedNIOTransportServicesProduct],
            packageRef: packageRef
        )
    }
}
