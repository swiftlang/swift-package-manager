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
    // MARK: - swift-asn1 Package

    static func createSwiftlySwiftASN1Package() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-asn1")

        // Modules
        let swiftASN1Module = self.createSwiftModule(name: "SwiftASN1")

        // Products
        let swiftASN1Product = try Product(
            package: identity,
            name: "SwiftASN1",
            type: .library(.automatic),
            modules: [swiftASN1Module]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-asn1",
            path: "/swift-asn1",
            modules: [swiftASN1Module],
            products: [swiftASN1Product]
        )

        // Resolved modules
        let resolvedSwiftASN1Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftASN1Module
        )

        // Resolved products
        let resolvedSwiftASN1Product = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftASN1Product,
            modules: IdentifiableSet([resolvedSwiftASN1Module])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedSwiftASN1Module]),
            products: [resolvedSwiftASN1Product]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-asn1.git"))
        )

        return (
            package: package,
            modules: [swiftASN1Module],
            products: [swiftASN1Product],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedSwiftASN1Module],
            resolvedProducts: [resolvedSwiftASN1Product],
            packageRef: packageRef
        )
    }

    // MARK: - swift-crypto Package

    static func createSwiftlySwiftCryptoPackage(
        swiftASN1Product: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-crypto")

        // Modules
        let cCryptoBoringSSLModule = self.createSwiftModule(name: "CCryptoBoringSSL")
        let cCryptoBoringSSLShimsModule = self.createSwiftModule(name: "CCryptoBoringSSLShims")
        let cryptoBoringWrapperModule = self.createSwiftModule(name: "CryptoBoringWrapper")
        let cryptoModule = self.createSwiftModule(name: "Crypto")
        let cryptoExtrasModule = self.createSwiftModule(name: "_CryptoExtras")

        // Products
        let cryptoProduct = try Product(
            package: identity,
            name: "Crypto",
            type: .library(.automatic),
            modules: [cryptoModule]
        )

        let cryptoExtrasProduct = try Product(
            package: identity,
            name: "_CryptoExtras",
            type: .library(.automatic),
            modules: [cryptoExtrasModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-crypto",
            path: "/swift-crypto",
            modules: [
                cCryptoBoringSSLModule, cCryptoBoringSSLShimsModule, cryptoBoringWrapperModule,
                cryptoModule, cryptoExtrasModule,
            ],
            products: [cryptoProduct, cryptoExtrasProduct]
        )

        // Resolved modules
        let resolvedCCryptoBoringSSLModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cCryptoBoringSSLModule
        )

        let resolvedCCryptoBoringSSLShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cCryptoBoringSSLShimsModule,
            dependencies: [
                .module(resolvedCCryptoBoringSSLModule, conditions: []),
            ]
        )

        let resolvedCryptoBoringWrapperModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cryptoBoringWrapperModule,
            dependencies: [
                .module(resolvedCCryptoBoringSSLModule, conditions: []),
                .module(resolvedCCryptoBoringSSLShimsModule, conditions: []),
            ]
        )

        let resolvedCryptoModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cryptoModule,
            dependencies: [
                .module(resolvedCCryptoBoringSSLModule, conditions: []),
                .module(resolvedCCryptoBoringSSLShimsModule, conditions: []),
                .module(resolvedCryptoBoringWrapperModule, conditions: []),
            ]
        )

        let resolvedCryptoExtrasModule = self.createResolvedModule(
            packageIdentity: identity,
            module: cryptoExtrasModule,
            dependencies: [
                .module(resolvedCCryptoBoringSSLModule, conditions: []),
                .module(resolvedCCryptoBoringSSLShimsModule, conditions: []),
                .module(resolvedCryptoBoringWrapperModule, conditions: []),
                .module(resolvedCryptoModule, conditions: []),
                .product(swiftASN1Product, conditions: []),
            ]
        )

        // Resolved products
        let resolvedCryptoProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: cryptoProduct,
            modules: IdentifiableSet([resolvedCryptoModule])
        )

        let resolvedCryptoExtrasProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: cryptoExtrasProduct,
            modules: IdentifiableSet([resolvedCryptoExtrasModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedCCryptoBoringSSLModule, resolvedCCryptoBoringSSLShimsModule,
                resolvedCryptoBoringWrapperModule, resolvedCryptoModule, resolvedCryptoExtrasModule,
            ]),
            products: [resolvedCryptoProduct, resolvedCryptoExtrasProduct],
            dependencies: [PackageIdentity.plain("swift-asn1")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-crypto.git"))
        )

        return (
            package: package,
            modules: [
                cCryptoBoringSSLModule, cCryptoBoringSSLShimsModule, cryptoBoringWrapperModule,
                cryptoModule, cryptoExtrasModule,
            ],
            products: [cryptoProduct, cryptoExtrasProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedCCryptoBoringSSLModule, resolvedCCryptoBoringSSLShimsModule,
                resolvedCryptoBoringWrapperModule, resolvedCryptoModule, resolvedCryptoExtrasModule,
            ],
            resolvedProducts: [resolvedCryptoProduct, resolvedCryptoExtrasProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-certificates Package

    static func createSwiftlySwiftCertificatesPackage(
        swiftASN1Product: ResolvedProduct,
        cryptoProduct: ResolvedProduct,
        cryptoExtrasProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-certificates")

        // Modules
        let certificateInternalsModule = self.createSwiftModule(name: "_CertificateInternals")
        let x509Module = self.createSwiftModule(name: "X509")

        // Products
        let x509Product = try Product(
            package: identity,
            name: "X509",
            type: .library(.automatic),
            modules: [x509Module]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "swift-certificates",
            path: "/swift-certificates",
            modules: [certificateInternalsModule, x509Module],
            products: [x509Product]
        )

        // Resolved modules
        let resolvedCertificateInternalsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: certificateInternalsModule
        )

        let resolvedX509Module = self.createResolvedModule(
            packageIdentity: identity,
            module: x509Module,
            dependencies: [
                .module(resolvedCertificateInternalsModule, conditions: []),
                .product(swiftASN1Product, conditions: []),
                .product(cryptoProduct, conditions: []),
                .product(cryptoExtrasProduct, conditions: []),
            ]
        )

        // Resolved products
        let resolvedX509Product = self.createResolvedProduct(
            packageIdentity: identity,
            product: x509Product,
            modules: IdentifiableSet([resolvedX509Module])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedCertificateInternalsModule, resolvedX509Module]),
            products: [resolvedX509Product],
            dependencies: [
                PackageIdentity.plain("swift-asn1"),
                PackageIdentity.plain("swift-crypto"),
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/apple/swift-certificates.git"))
        )

        return (
            package: package,
            modules: [certificateInternalsModule, x509Module],
            products: [x509Product],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedCertificateInternalsModule, resolvedX509Module],
            resolvedProducts: [resolvedX509Product],
            packageRef: packageRef
        )
    }
}
