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
    // MARK: - Root SPM Package - Part 2: Command & Support Modules

    /// Creates command, support, and plugin modules for the root SwiftPM package
    /// These include Commands, XCBuildSupport, SwiftBuildSupport, PackagePlugin, etc.
    static func createSPMRootCommandModules(
        coreResolvedModules: [ResolvedModule],
        argumentParserProduct: ResolvedProduct,
        orderedCollectionsProduct: ResolvedProduct,
        tscBasicProduct: ResolvedProduct,
        swiftIDEUtilsProduct: ResolvedProduct,
        swiftRefactorProduct: ResolvedProduct,
        swiftDiagnosticsProduct: ResolvedProduct,
        swiftParserProduct: ResolvedProduct,
        swiftSyntaxProduct: ResolvedProduct,
        swiftBuildProduct: ResolvedProduct,
        swbBuildServiceProduct: ResolvedProduct
    ) -> (
        modules: [Module],
        resolvedModules: [ResolvedModule]
    ) {
        let identity = PackageIdentity.plain("swift-package-manager")

        // Extract core resolved modules we need
        let resolvedBasicsModule = coreResolvedModules.first { $0.name == "Basics" }!
        let resolvedBinarySymbolsModule = coreResolvedModules.first { $0.name == "BinarySymbols" }!
        let resolvedBuildModule = coreResolvedModules.first { $0.name == "Build" }!
        let resolvedPackageModelModule = coreResolvedModules.first { $0.name == "PackageModel" }!
        let resolvedPackageLoadingModule = coreResolvedModules.first { $0.name == "PackageLoading" }!
        let resolvedPackageGraphModule = coreResolvedModules.first { $0.name == "PackageGraph" }!
        let resolvedPackageCollectionsModule = coreResolvedModules.first { $0.name == "PackageCollections" }!
        _ = coreResolvedModules.first { $0.name == "PackageCollectionsModel" }!
        let resolvedPackageRegistryModule = coreResolvedModules.first { $0.name == "PackageRegistry" }!
        let resolvedPackageSigningModule = coreResolvedModules.first { $0.name == "PackageSigning" }!
        let resolvedSourceControlModule = coreResolvedModules.first { $0.name == "SourceControl" }!
        let resolvedWorkspaceModule = coreResolvedModules.first { $0.name == "Workspace" }!
        let resolvedSBOMModelModule = coreResolvedModules.first { $0.name == "SBOMModel" }!
        let resolvedSPMBuildCoreModule = coreResolvedModules.first { $0.name == "SPMBuildCore" }!

        // MARK: - Create Command & Support Modules

        let xcBuildSupportModule = self.createSwiftModule(name: "XCBuildSupport")
        let swiftBuildSupportModule = self.createSwiftModule(name: "SwiftBuildSupport")
        let swiftFixItModule = self.createSwiftModule(name: "SwiftFixIt")
        let coreCommandsModule = self.createSwiftModule(name: "CoreCommands")
        let commandsModule = self.createSwiftModule(name: "Commands")
        let packageCollectionsCommandModule = self.createSwiftModule(name: "PackageCollectionsCommand")
        let swiftSDKCommandModule = self.createSwiftModule(name: "SwiftSDKCommand")
        let packageRegistryCommandModule = self.createSwiftModule(name: "PackageRegistryCommand")
        let packageDescriptionModule = self.createSwiftModule(name: "PackageDescription")
        let compilerPluginSupportModule = self.createSwiftModule(name: "CompilerPluginSupport")
        let packagePluginModule = self.createSwiftModule(name: "PackagePlugin")
        let appleProductTypesModule = self.createSwiftModule(name: "AppleProductTypes")
        let packageManagerDocsModule = self.createSwiftModule(name: "PackageManagerDocs")

        // Test support modules
        let internalTestSupportModule = self.createSwiftModule(name: "_InternalTestSupport")
        let integrationTestSupportModule = self.createSwiftModule(name: "_IntegrationTestSupport")
        let internalBuildTestSupportModule = self.createSwiftModule(name: "_InternalBuildTestSupport")
        let tsanUtilsModule = self.createSwiftModule(name: "tsan_utils")

        // MARK: - Create Resolved Modules with Dependencies

        let resolvedXCBuildSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: xcBuildSupportModule,
            dependencies: [
                .module(resolvedSPMBuildCoreModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
            ]
        )

        let resolvedSwiftBuildSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBuildSupportModule,
            dependencies: [
                .module(resolvedSPMBuildCoreModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .product(swiftBuildProduct, conditions: []),
                .product(swbBuildServiceProduct, conditions: []),
            ]
        )

        let resolvedSwiftFixItModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftFixItModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .product(tscBasicProduct, conditions: []),
                .product(swiftDiagnosticsProduct, conditions: []),
                .product(swiftIDEUtilsProduct, conditions: []),
                .product(swiftParserProduct, conditions: []),
                .product(swiftSyntaxProduct, conditions: []),
            ]
        )

        let resolvedCoreCommandsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: coreCommandsModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedBuildModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedWorkspaceModule, conditions: []),
                .module(resolvedXCBuildSupportModule, conditions: []),
                .module(resolvedSwiftBuildSupportModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedCommandsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: commandsModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedBinarySymbolsModule, conditions: []),
                .module(resolvedBuildModule, conditions: []),
                .module(resolvedCoreCommandsModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedSBOMModelModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
                .module(resolvedWorkspaceModule, conditions: []),
                .module(resolvedXCBuildSupportModule, conditions: []),
                .module(resolvedSwiftBuildSupportModule, conditions: []),
                .module(resolvedSwiftFixItModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
                .product(swiftIDEUtilsProduct, conditions: []),
                .product(swiftRefactorProduct, conditions: []),
            ]
        )

        let resolvedPackageCollectionsCommandModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageCollectionsCommandModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedCoreCommandsModule, conditions: []),
                .module(resolvedPackageCollectionsModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedSwiftSDKCommandModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSDKCommandModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedCoreCommandsModule, conditions: []),
                .module(resolvedSPMBuildCoreModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedPackageRegistryCommandModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageRegistryCommandModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedCoreCommandsModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedPackageRegistryModule, conditions: []),
                .module(resolvedPackageSigningModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
                .module(resolvedSPMBuildCoreModule, conditions: []),
                .module(resolvedWorkspaceModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedPackageDescriptionModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageDescriptionModule
        )

        let resolvedCompilerPluginSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: compilerPluginSupportModule,
            dependencies: [.module(resolvedPackageDescriptionModule, conditions: [])]
        )

        let resolvedPackagePluginModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packagePluginModule
        )

        let resolvedAppleProductTypesModule = self.createResolvedModule(
            packageIdentity: identity,
            module: appleProductTypesModule,
            dependencies: [.module(resolvedPackageDescriptionModule, conditions: [])]
        )

        let resolvedPackageManagerDocsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageManagerDocsModule
        )

        // Test support modules
        let resolvedInternalTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: internalTestSupportModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .module(resolvedPackageRegistryModule, conditions: []),
                .module(resolvedPackageSigningModule, conditions: []),
                .module(resolvedSourceControlModule, conditions: []),
                .module(resolvedWorkspaceModule, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
            ]
        )

        let resolvedIntegrationTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: integrationTestSupportModule,
            dependencies: [.module(resolvedInternalTestSupportModule, conditions: [])]
        )

        let resolvedInternalBuildTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: internalBuildTestSupportModule,
            dependencies: [
                .module(resolvedBuildModule, conditions: []),
                .module(resolvedXCBuildSupportModule, conditions: []),
                .module(resolvedSwiftBuildSupportModule, conditions: []),
                .module(resolvedInternalTestSupportModule, conditions: []),
            ]
        )

        let resolvedTsanUtilsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: tsanUtilsModule
        )

        return (
            modules: [
                xcBuildSupportModule, swiftBuildSupportModule, swiftFixItModule, coreCommandsModule,
                commandsModule, packageCollectionsCommandModule, swiftSDKCommandModule,
                packageRegistryCommandModule, packageDescriptionModule, compilerPluginSupportModule,
                packagePluginModule, appleProductTypesModule, packageManagerDocsModule,
                internalTestSupportModule, integrationTestSupportModule, internalBuildTestSupportModule,
                tsanUtilsModule,
            ],
            resolvedModules: [
                resolvedXCBuildSupportModule, resolvedSwiftBuildSupportModule, resolvedSwiftFixItModule,
                resolvedCoreCommandsModule, resolvedCommandsModule, resolvedPackageCollectionsCommandModule,
                resolvedSwiftSDKCommandModule, resolvedPackageRegistryCommandModule, resolvedPackageDescriptionModule,
                resolvedCompilerPluginSupportModule, resolvedPackagePluginModule, resolvedAppleProductTypesModule,
                resolvedPackageManagerDocsModule, resolvedInternalTestSupportModule,
                resolvedIntegrationTestSupportModule,
                resolvedInternalBuildTestSupportModule, resolvedTsanUtilsModule,
            ]
        )
    }
}
