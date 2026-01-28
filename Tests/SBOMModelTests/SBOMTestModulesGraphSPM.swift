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
    /// Creates a complete SPM ModulesGraph with all dependencies including the root SwiftPM package
    /// This assembles all the individual package fixtures into a complete dependency graph
    /// The root package includes the SwiftPMDataModel product that was previously missing
    static func createSPMModulesGraph(rootPath: String = "/swift-package-manager") throws -> ModulesGraph {
        // MARK: - Create all foundation packages

        let systemPackage = try createSPMSwiftSystemPackage()
        let collectionsPackage = try createSPMSwiftCollectionsPackage()
        let argumentParserPackage = try createSPMSwiftArgumentParserPackage()
        let sqlitePackage = try createSPMSwiftToolchainSQLitePackage()

        // MARK: - Create build tooling packages

        let llbuildPackage = try createSPMSwiftLLBuildPackage(
            swiftToolchainCSQLiteProduct: sqlitePackage.resolvedProducts[0]
        )

        let toolsSupportPackage = try createSPMSwiftToolsSupportCorePackage()

        let driverPackage = try createSPMSwiftDriverPackage(
            swiftToolsSupportAutoProduct: toolsSupportPackage.resolvedProducts[2],
            llbuildSwiftProduct: llbuildPackage.resolvedProducts[3],
            argumentParserProduct: argumentParserPackage.resolvedProducts[0]
        )

        // MARK: - Create security packages

        let asn1Package = try createSPMSwiftASN1Package()

        let cryptoPackage = try createSPMSwiftCryptoPackage(
            swiftASN1Product: asn1Package.resolvedProducts[0]
        )

        let certificatesPackage = try createSPMSwiftCertificatesPackage(
            swiftASN1Product: asn1Package.resolvedProducts[0],
            cryptoProduct: cryptoPackage.resolvedProducts[0],
            cryptoExtrasProduct: cryptoPackage.resolvedProducts[1]
        )

        // MARK: - Create documentation packages

        let symbolKitPackage = try createSPMSwiftDoccSymbolKitPackage()

        let doccPluginPackage = try createSPMSwiftDoccPluginPackage(
            symbolKitProduct: symbolKitPackage.resolvedProducts[0]
        )

        // MARK: - Create swift-syntax package

        let syntaxPackage = try createSPMSwiftSyntaxPackage()

        // MARK: - Create swift-build package

        let buildPackage = try createSPMSwiftBuildPackage(
            swiftSyntaxProduct: syntaxPackage.resolvedProducts[0],
            swiftParserProduct: syntaxPackage.resolvedProducts[2],
            swiftDriverProduct: driverPackage.resolvedProducts[0],
            swiftDriverExecutionProduct: driverPackage.resolvedProducts[2],
            llbuildSwiftProduct: llbuildPackage.resolvedProducts[3],
            swiftToolsSupportAutoProduct: toolsSupportPackage.resolvedProducts[2],
            argumentParserProduct: argumentParserPackage.resolvedProducts[0],
            systemPackageProduct: systemPackage.resolvedProducts[0],
            cryptoProduct: cryptoPackage.resolvedProducts[0],
            x509Product: certificatesPackage.resolvedProducts[0]
        )

        // MARK: - Create ROOT SwiftPM package (with SwiftPMDataModel product)

        let rootPackage = try createSPMRootPackageComplete(
            rootPath: rootPath,
            systemPackageProduct: systemPackage.resolvedProducts[0],
            dequeModuleProduct: collectionsPackage.resolvedProducts[0],
            orderedCollectionsProduct: collectionsPackage.resolvedProducts[6],
            argumentParserProduct: argumentParserPackage.resolvedProducts[0],
            llbuildSwiftProduct: llbuildPackage.resolvedProducts[3],
            swiftDriverProduct: driverPackage.resolvedProducts[0],
            swiftToolsSupportAutoProduct: toolsSupportPackage.resolvedProducts[2],
            tscBasicProduct: toolsSupportPackage.resolvedProducts[0],
            tscTestSupportProduct: toolsSupportPackage.resolvedProducts[3],
            cryptoProduct: cryptoPackage.resolvedProducts[0],
            x509Product: certificatesPackage.resolvedProducts[0],
            swiftToolchainCSQLiteProduct: sqlitePackage.resolvedProducts[0],
            swiftIDEUtilsProduct: syntaxPackage.resolvedProducts[7],
            swiftRefactorProduct: syntaxPackage.resolvedProducts[8],
            swiftDiagnosticsProduct: syntaxPackage.resolvedProducts[3],
            swiftParserProduct: syntaxPackage.resolvedProducts[2],
            swiftSyntaxProduct: syntaxPackage.resolvedProducts[0],
            swiftBuildProduct: buildPackage.resolvedProducts[5],
            swbBuildServiceProduct: buildPackage.resolvedProducts[0]
        )

        // MARK: - Assemble all packages

        let allResolvedPackages: IdentifiableSet<ResolvedPackage> = IdentifiableSet([
            rootPackage.resolvedPackage,
            buildPackage.resolvedPackage,
            syntaxPackage.resolvedPackage,
            driverPackage.resolvedPackage,
            llbuildPackage.resolvedPackage,
            toolsSupportPackage.resolvedPackage,
            argumentParserPackage.resolvedPackage,
            systemPackage.resolvedPackage,
            collectionsPackage.resolvedPackage,
            sqlitePackage.resolvedPackage,
            asn1Package.resolvedPackage,
            cryptoPackage.resolvedPackage,
            certificatesPackage.resolvedPackage,
            symbolKitPackage.resolvedPackage,
            doccPluginPackage.resolvedPackage,
        ])

        let rootDependencies = [
            buildPackage.resolvedPackage,
            syntaxPackage.resolvedPackage,
            driverPackage.resolvedPackage,
            llbuildPackage.resolvedPackage,
            toolsSupportPackage.resolvedPackage,
            argumentParserPackage.resolvedPackage,
            systemPackage.resolvedPackage,
            collectionsPackage.resolvedPackage,
            sqlitePackage.resolvedPackage,
            asn1Package.resolvedPackage,
            cryptoPackage.resolvedPackage,
            certificatesPackage.resolvedPackage,
            symbolKitPackage.resolvedPackage,
            doccPluginPackage.resolvedPackage,
        ]

        let packageReferences = [
            rootPackage.packageRef,
            buildPackage.packageRef,
            syntaxPackage.packageRef,
            driverPackage.packageRef,
            llbuildPackage.packageRef,
            toolsSupportPackage.packageRef,
            argumentParserPackage.packageRef,
            systemPackage.packageRef,
            collectionsPackage.packageRef,
            sqlitePackage.packageRef,
            asn1Package.packageRef,
            cryptoPackage.packageRef,
            certificatesPackage.packageRef,
            symbolKitPackage.packageRef,
            doccPluginPackage.packageRef,
        ]

        // MARK: - Create and return ModulesGraph

        return try ModulesGraph(
            rootPackages: [rootPackage.resolvedPackage],
            rootDependencies: rootDependencies,
            packages: allResolvedPackages,
            dependencies: packageReferences,
            binaryArtifacts: [:]
        )
    }
}
