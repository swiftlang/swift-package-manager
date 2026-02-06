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
    /// Creates a complete ModulesGraph for the Swiftly project with all dependencies
    static func createSwiftlyModulesGraph(rootPath: String = "/tmp/swiftly-mock") throws -> ModulesGraph {
        // MARK: - Create Foundation Packages (no dependencies)

        let systemPackage = try createSwiftSystemPackage()
        let argumentParserPackage = try createSwiftArgumentParserPackage()
        let toolsSupportPackage = try createSwiftToolsSupportCorePackage()
        let httpTypesPackage = try createSwiftHTTPTypesPackage()

        // MARK: - Create Security Packages

        let asn1Package = try createSwiftlySwiftASN1Package()

        let cryptoPackage = try createSwiftlySwiftCryptoPackage(
            swiftASN1Product: asn1Package.resolvedProducts[0]
        )

        let certificatesPackage = try createSwiftlySwiftCertificatesPackage(
            swiftASN1Product: asn1Package.resolvedProducts[0],
            cryptoProduct: cryptoPackage.resolvedProducts[0],
            cryptoExtrasProduct: cryptoPackage.resolvedProducts[1]
        )

        // MARK: - Create Packages with Foundation Dependencies

        let subprocessPackage = try createSwiftSubprocessPackage(
            systemPackageProduct: systemPackage.resolvedProducts[0]
        )

        // MARK: - Create Collections and Utility Packages

        let collectionsPackage = try createSwiftCollectionsPackage()
        let numericsPackage = try createSwiftNumericsPackage()
        let algorithmsPackage = try createSwiftAlgorithmsPackage(
            realModuleProduct: numericsPackage.resolvedProducts[0]
        )
        let atomicsPackage = try createSwiftAtomicsPackage()

        let logPackage = try createSwiftLogPackage()
        let serviceContextPackage = try createSwiftServiceContextPackage()
        let distributedTracingPackage = try createSwiftDistributedTracingPackage(
            serviceContextProduct: serviceContextPackage.resolvedProducts[0]
        )
        let yamsPackage = try createYamsPackage()
        let openAPIKitPackage = try createOpenAPIKitPackage()

        // MARK: - Create NIO Packages

        let nioPackage = try createSwiftNIOPackage(
            atomicsProduct: atomicsPackage.resolvedProducts[0],
            dequeProduct: collectionsPackage.resolvedProducts[0], // DequeModule
            systemPackageProduct: systemPackage.resolvedProducts[0]
        )

        let nioSSLPackage = try createSwiftNIOSSLPackage(
            nioProduct: nioPackage.resolvedProducts[2], // NIO
            nioCoreProduct: nioPackage.resolvedProducts[1], // NIOCore
            nioConcurrencyHelpersProduct: nioPackage.resolvedProducts[0], // NIOConcurrencyHelpers
            nioTLSProduct: nioPackage.resolvedProducts[4] // NIOTLS
        )

        let nioHTTP2Package = try createSwiftNIOHTTP2Package(
            nioProduct: nioPackage.resolvedProducts[2], // NIO
            nioCoreProduct: nioPackage.resolvedProducts[1], // NIOCore
            nioConcurrencyHelpersProduct: nioPackage.resolvedProducts[0], // NIOConcurrencyHelpers
            nioHTTP1Product: nioPackage.resolvedProducts[5], // NIOHTTP1
            nioTLSProduct: nioPackage.resolvedProducts[4], // NIOTLS
            atomicsProduct: atomicsPackage.resolvedProducts[0]
        )

        let nioExtrasPackage = try createSwiftNIOExtrasPackage(
            nioProduct: nioPackage.resolvedProducts[2], // NIO
            nioCoreProduct: nioPackage.resolvedProducts[1], // NIOCore
            nioHTTP1Product: nioPackage.resolvedProducts[5] // NIOHTTP1
        )

        let nioTransportServicesPackage = try createSwiftNIOTransportServicesPackage(
            nioProduct: nioPackage.resolvedProducts[2], // NIO
            nioCoreProduct: nioPackage.resolvedProducts[1], // NIOCore
            nioFoundationCompatProduct: nioPackage.resolvedProducts[6], // NIOFoundationCompat
            nioTLSProduct: nioPackage.resolvedProducts[4], // NIOTLS
            atomicsProduct: atomicsPackage.resolvedProducts[0]
        )

        // MARK: - Create OpenAPI Packages

        let openAPIRuntimePackage = try createSwiftOpenAPIRuntimePackage(
            httpTypesProduct: httpTypesPackage.resolvedProducts[0]
        )

        let openAPIGeneratorPackage = try createSwiftOpenAPIGeneratorPackage(
            openAPIKitProduct: openAPIKitPackage.resolvedProducts[0], // OpenAPIKit
            openAPIKit30Product: openAPIKitPackage.resolvedProducts[1], // OpenAPIKit30
            openAPIKitCompatProduct: openAPIKitPackage.resolvedProducts[2], // OpenAPIKitCompat
            algorithmsProduct: algorithmsPackage.resolvedProducts[0],
            orderedCollectionsProduct: collectionsPackage.resolvedProducts[1], // OrderedCollections
            yamsProduct: yamsPackage.resolvedProducts[0],
            argumentParserProduct: argumentParserPackage.resolvedProducts[0]
        )

        let asyncHTTPClientPackage = try createAsyncHTTPClientPackage(
            nioProduct: nioPackage.resolvedProducts[2], // NIO
            nioTLSProduct: nioPackage.resolvedProducts[4], // NIOTLS
            nioCoreProduct: nioPackage.resolvedProducts[1], // NIOCore
            nioPosixProduct: nioPackage.resolvedProducts[3], // NIOPosix
            nioHTTP1Product: nioPackage.resolvedProducts[5], // NIOHTTP1
            nioConcurrencyHelpersProduct: nioPackage.resolvedProducts[0], // NIOConcurrencyHelpers
            nioHTTP2Product: nioHTTP2Package.resolvedProducts[0], // NIOHTTP2
            nioSSLProduct: nioSSLPackage.resolvedProducts[0], // NIOSSL
            nioHTTPCompressionProduct: nioExtrasPackage.resolvedProducts[0], // NIOHTTPCompression
            nioSOCKSProduct: nioExtrasPackage.resolvedProducts[1], // NIOSOCKS
            nioTransportServicesProduct: nioTransportServicesPackage.resolvedProducts[0],
            atomicsProduct: atomicsPackage.resolvedProducts[0],
            algorithmsProduct: algorithmsPackage.resolvedProducts[0],
            loggingProduct: logPackage.resolvedProducts[0],
            tracingProduct: distributedTracingPackage.resolvedProducts[0]
        )

        let openAPIAsyncHTTPClientPackage = try createSwiftOpenAPIAsyncHTTPClientPackage(
            openAPIRuntimeProduct: openAPIRuntimePackage.resolvedProducts[0],
            httpTypesProduct: httpTypesPackage.resolvedProducts[0],
            asyncHTTPClientProduct: asyncHTTPClientPackage.resolvedProducts[0],
            nioFoundationCompatProduct: nioPackage.resolvedProducts[6] // NIOFoundationCompat
        )

        // MARK: - Create Swiftly Root Package

        let swiftlyPackage = try createSwiftlyRootPackage(
            rootPath: rootPath,
            openAPIGeneratorProduct: openAPIGeneratorPackage.resolvedProducts[0], // OpenAPIGenerator
            openAPIRuntimeProduct: openAPIRuntimePackage.resolvedProducts[0],
            argumentParserProduct: argumentParserPackage.resolvedProducts[0],
            systemPackageProduct: systemPackage.resolvedProducts[0],
            asyncHTTPClientProduct: asyncHTTPClientPackage.resolvedProducts[0],
            nioFoundationCompatProduct: nioPackage.resolvedProducts[6], // NIOFoundationCompat
            openAPIAsyncHTTPClientProduct: openAPIAsyncHTTPClientPackage.resolvedProducts[0],
            subprocessProduct: subprocessPackage.resolvedProducts[0],
            swiftToolsSupportProduct: toolsSupportPackage.resolvedProducts[0],
            nioFileSystemProduct: nioPackage.resolvedProducts[7] // _NIOFileSystem
        )

        // MARK: - Assemble All Packages

        let allResolvedPackages: IdentifiableSet<ResolvedPackage> = IdentifiableSet([
            swiftlyPackage.resolvedPackage,
            systemPackage.resolvedPackage,
            subprocessPackage.resolvedPackage,
            argumentParserPackage.resolvedPackage,
            toolsSupportPackage.resolvedPackage,
            httpTypesPackage.resolvedPackage,
            asn1Package.resolvedPackage,
            cryptoPackage.resolvedPackage,
            certificatesPackage.resolvedPackage,
            collectionsPackage.resolvedPackage,
            numericsPackage.resolvedPackage,
            algorithmsPackage.resolvedPackage,
            atomicsPackage.resolvedPackage,
            logPackage.resolvedPackage,
            serviceContextPackage.resolvedPackage,
            distributedTracingPackage.resolvedPackage,
            yamsPackage.resolvedPackage,
            openAPIKitPackage.resolvedPackage,
            nioPackage.resolvedPackage,
            nioSSLPackage.resolvedPackage,
            nioHTTP2Package.resolvedPackage,
            nioExtrasPackage.resolvedPackage,
            nioTransportServicesPackage.resolvedPackage,
            openAPIRuntimePackage.resolvedPackage,
            openAPIGeneratorPackage.resolvedPackage,
            asyncHTTPClientPackage.resolvedPackage,
            openAPIAsyncHTTPClientPackage.resolvedPackage,
        ])

        let rootDependencies = [
            systemPackage.resolvedPackage,
            subprocessPackage.resolvedPackage,
            argumentParserPackage.resolvedPackage,
            toolsSupportPackage.resolvedPackage,
            httpTypesPackage.resolvedPackage,
            asn1Package.resolvedPackage,
            cryptoPackage.resolvedPackage,
            certificatesPackage.resolvedPackage,
            collectionsPackage.resolvedPackage,
            numericsPackage.resolvedPackage,
            algorithmsPackage.resolvedPackage,
            atomicsPackage.resolvedPackage,
            logPackage.resolvedPackage,
            serviceContextPackage.resolvedPackage,
            distributedTracingPackage.resolvedPackage,
            yamsPackage.resolvedPackage,
            openAPIKitPackage.resolvedPackage,
            nioPackage.resolvedPackage,
            nioSSLPackage.resolvedPackage,
            nioHTTP2Package.resolvedPackage,
            nioExtrasPackage.resolvedPackage,
            nioTransportServicesPackage.resolvedPackage,
            openAPIRuntimePackage.resolvedPackage,
            openAPIGeneratorPackage.resolvedPackage,
            asyncHTTPClientPackage.resolvedPackage,
            openAPIAsyncHTTPClientPackage.resolvedPackage,
        ]

        let packageReferences = [
            swiftlyPackage.packageRef,
            systemPackage.packageRef,
            subprocessPackage.packageRef,
            argumentParserPackage.packageRef,
            toolsSupportPackage.packageRef,
            httpTypesPackage.packageRef,
            asn1Package.packageRef,
            cryptoPackage.packageRef,
            certificatesPackage.packageRef,
            collectionsPackage.packageRef,
            numericsPackage.packageRef,
            algorithmsPackage.packageRef,
            atomicsPackage.packageRef,
            logPackage.packageRef,
            serviceContextPackage.packageRef,
            distributedTracingPackage.packageRef,
            yamsPackage.packageRef,
            openAPIKitPackage.packageRef,
            nioPackage.packageRef,
            nioSSLPackage.packageRef,
            nioHTTP2Package.packageRef,
            nioExtrasPackage.packageRef,
            nioTransportServicesPackage.packageRef,
            openAPIRuntimePackage.packageRef,
            openAPIGeneratorPackage.packageRef,
            asyncHTTPClientPackage.packageRef,
            openAPIAsyncHTTPClientPackage.packageRef,
        ]

        // MARK: - Create ModulesGraph

        return try ModulesGraph(
            rootPackages: [swiftlyPackage.resolvedPackage],
            rootDependencies: rootDependencies,
            packages: allResolvedPackages,
            dependencies: packageReferences,
            binaryArtifacts: [:]
        )
    }
}
