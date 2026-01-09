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
    // MARK: - swift-syntax Package (26 modules)

    static func createSPMSwiftSyntaxPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-syntax")

        // MARK: - Create all 26 modules

        // Base/Support modules
        let swiftSyntaxCShimsModule = self.createSwiftModule(name: "_SwiftSyntaxCShims")
        let swiftSyntax509Module = self.createSwiftModule(name: "SwiftSyntax509")
        let swiftSyntax510Module = self.createSwiftModule(name: "SwiftSyntax510")
        let swiftSyntax600Module = self.createSwiftModule(name: "SwiftSyntax600")
        let swiftSyntax601Module = self.createSwiftModule(name: "SwiftSyntax601")
        let swiftSyntax602Module = self.createSwiftModule(name: "SwiftSyntax602")
        let swiftSyntax603Module = self.createSwiftModule(name: "SwiftSyntax603")
        let swiftSyntaxGenericTestSupportModule = self.createSwiftModule(name: "_SwiftSyntaxGenericTestSupport")
        let swiftLibraryPluginProviderCShimsModule = self.createSwiftModule(name: "_SwiftLibraryPluginProviderCShims")

        // Core modules
        let swiftSyntaxModule = self.createSwiftModule(name: "SwiftSyntax")
        let swiftDiagnosticsModule = self.createSwiftModule(name: "SwiftDiagnostics")
        let swiftParserModule = self.createSwiftModule(name: "SwiftParser")
        let swiftBasicFormatModule = self.createSwiftModule(name: "SwiftBasicFormat")
        let swiftOperatorsModule = self.createSwiftModule(name: "SwiftOperators")
        let swiftParserDiagnosticsModule = self.createSwiftModule(name: "SwiftParserDiagnostics")
        let swiftSyntaxBuilderModule = self.createSwiftModule(name: "SwiftSyntaxBuilder")

        // Advanced modules
        let swiftIDEUtilsModule = self.createSwiftModule(name: "SwiftIDEUtils")
        let swiftIfConfigModule = self.createSwiftModule(name: "SwiftIfConfig")
        let swiftLexicalLookupModule = self.createSwiftModule(name: "SwiftLexicalLookup")
        let swiftRefactorModule = self.createSwiftModule(name: "SwiftRefactor")
        let swiftSyntaxMacrosModule = self.createSwiftModule(name: "SwiftSyntaxMacros")
        let swiftSyntaxMacroExpansionModule = self.createSwiftModule(name: "SwiftSyntaxMacroExpansion")

        // Compiler/Plugin modules
        let swiftCompilerPluginMessageHandlingModule = self
            .createSwiftModule(name: "SwiftCompilerPluginMessageHandling")
        let swiftCompilerPluginModule = self.createSwiftModule(name: "SwiftCompilerPlugin")
        let swiftLibraryPluginProviderModule = self.createSwiftModule(name: "SwiftLibraryPluginProvider")

        // Test support modules
        let swiftSyntaxMacrosGenericTestSupportModule = self
            .createSwiftModule(name: "SwiftSyntaxMacrosGenericTestSupport")
        let swiftSyntaxMacrosTestSupportModule = self.createSwiftModule(name: "SwiftSyntaxMacrosTestSupport")

        // MARK: - Create products (18 products)

        let swiftSyntaxProduct = try Product(
            package: identity,
            name: "SwiftSyntax",
            type: .library(.automatic),
            modules: [swiftSyntaxModule]
        )
        let swiftDiagnosticsProduct = try Product(
            package: identity,
            name: "SwiftDiagnostics",
            type: .library(.automatic),
            modules: [swiftDiagnosticsModule]
        )
        let swiftParserProduct = try Product(
            package: identity,
            name: "SwiftParser",
            type: .library(.automatic),
            modules: [swiftParserModule]
        )
        let swiftBasicFormatProduct = try Product(
            package: identity,
            name: "SwiftBasicFormat",
            type: .library(.automatic),
            modules: [swiftBasicFormatModule]
        )
        let swiftOperatorsProduct = try Product(
            package: identity,
            name: "SwiftOperators",
            type: .library(.automatic),
            modules: [swiftOperatorsModule]
        )
        let swiftParserDiagnosticsProduct = try Product(
            package: identity,
            name: "SwiftParserDiagnostics",
            type: .library(.automatic),
            modules: [swiftParserDiagnosticsModule]
        )
        let swiftSyntaxBuilderProduct = try Product(
            package: identity,
            name: "SwiftSyntaxBuilder",
            type: .library(.automatic),
            modules: [swiftSyntaxBuilderModule]
        )
        let swiftIDEUtilsProduct = try Product(
            package: identity,
            name: "SwiftIDEUtils",
            type: .library(.automatic),
            modules: [swiftIDEUtilsModule]
        )
        let swiftIfConfigProduct = try Product(
            package: identity,
            name: "SwiftIfConfig",
            type: .library(.automatic),
            modules: [swiftIfConfigModule]
        )
        let swiftLexicalLookupProduct = try Product(
            package: identity,
            name: "SwiftLexicalLookup",
            type: .library(.automatic),
            modules: [swiftLexicalLookupModule]
        )
        let swiftRefactorProduct = try Product(
            package: identity,
            name: "SwiftRefactor",
            type: .library(.automatic),
            modules: [swiftRefactorModule]
        )
        let swiftSyntaxMacrosProduct = try Product(
            package: identity,
            name: "SwiftSyntaxMacros",
            type: .library(.automatic),
            modules: [swiftSyntaxMacrosModule]
        )
        let swiftSyntaxMacroExpansionProduct = try Product(
            package: identity,
            name: "SwiftSyntaxMacroExpansion",
            type: .library(.automatic),
            modules: [swiftSyntaxMacroExpansionModule]
        )
        let swiftCompilerPluginProduct = try Product(
            package: identity,
            name: "SwiftCompilerPlugin",
            type: .library(.automatic),
            modules: [swiftCompilerPluginModule]
        )
        let swiftCompilerPluginMessageHandlingProduct = try Product(
            package: identity,
            name: "_SwiftCompilerPluginMessageHandling",
            type: .library(.automatic),
            modules: [swiftCompilerPluginMessageHandlingModule]
        )
        let swiftLibraryPluginProviderProduct = try Product(
            package: identity,
            name: "_SwiftLibraryPluginProvider",
            type: .library(.automatic),
            modules: [swiftLibraryPluginProviderModule]
        )
        let swiftSyntaxMacrosGenericTestSupportProduct = try Product(
            package: identity,
            name: "SwiftSyntaxMacrosGenericTestSupport",
            type: .library(.automatic),
            modules: [swiftSyntaxMacrosGenericTestSupportModule]
        )
        let swiftSyntaxMacrosTestSupportProduct = try Product(
            package: identity,
            name: "SwiftSyntaxMacrosTestSupport",
            type: .library(.automatic),
            modules: [swiftSyntaxMacrosTestSupportModule]
        )

        // MARK: - Create package

        let package = self.createPackage(
            identity: identity,
            displayName: "swift-syntax",
            path: "/swift-syntax",
            modules: [
                swiftSyntaxCShimsModule, swiftSyntax509Module, swiftSyntax510Module, swiftSyntax600Module,
                swiftSyntax601Module, swiftSyntax602Module, swiftSyntax603Module, swiftSyntaxGenericTestSupportModule,
                swiftLibraryPluginProviderCShimsModule, swiftSyntaxModule, swiftDiagnosticsModule, swiftParserModule,
                swiftBasicFormatModule, swiftOperatorsModule, swiftParserDiagnosticsModule, swiftSyntaxBuilderModule,
                swiftIDEUtilsModule, swiftIfConfigModule, swiftLexicalLookupModule, swiftRefactorModule,
                swiftSyntaxMacrosModule, swiftSyntaxMacroExpansionModule, swiftCompilerPluginMessageHandlingModule,
                swiftCompilerPluginModule, swiftLibraryPluginProviderModule, swiftSyntaxMacrosGenericTestSupportModule,
                swiftSyntaxMacrosTestSupportModule,
            ],
            products: [
                swiftSyntaxProduct, swiftDiagnosticsProduct, swiftParserProduct, swiftBasicFormatProduct,
                swiftOperatorsProduct, swiftParserDiagnosticsProduct, swiftSyntaxBuilderProduct, swiftIDEUtilsProduct,
                swiftIfConfigProduct, swiftLexicalLookupProduct, swiftRefactorProduct, swiftSyntaxMacrosProduct,
                swiftSyntaxMacroExpansionProduct, swiftCompilerPluginProduct, swiftCompilerPluginMessageHandlingProduct,
                swiftLibraryPluginProviderProduct, swiftSyntaxMacrosGenericTestSupportProduct,
                swiftSyntaxMacrosTestSupportProduct,
            ]
        )

        // MARK: - Create resolved modules with dependencies

        let resolvedSwiftSyntaxCShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxCShimsModule
        )
        let resolvedSwiftSyntax509Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntax509Module
        )
        let resolvedSwiftSyntax510Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntax510Module
        )
        let resolvedSwiftSyntax600Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntax600Module
        )
        let resolvedSwiftSyntax601Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntax601Module
        )
        let resolvedSwiftSyntax602Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntax602Module
        )
        let resolvedSwiftSyntax603Module = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntax603Module
        )
        let resolvedSwiftSyntaxGenericTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxGenericTestSupportModule
        )
        let resolvedSwiftLibraryPluginProviderCShimsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftLibraryPluginProviderCShimsModule
        )

        let resolvedSwiftSyntaxModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxModule,
            dependencies: [
                .module(resolvedSwiftSyntaxCShimsModule, conditions: []),
                .module(resolvedSwiftSyntax509Module, conditions: []),
                .module(resolvedSwiftSyntax510Module, conditions: []),
                .module(resolvedSwiftSyntax600Module, conditions: []),
                .module(resolvedSwiftSyntax601Module, conditions: []),
                .module(resolvedSwiftSyntax602Module, conditions: []),
                .module(resolvedSwiftSyntax603Module, conditions: []),
            ]
        )

        let resolvedSwiftDiagnosticsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftDiagnosticsModule,
            dependencies: [.module(resolvedSwiftSyntaxModule, conditions: [])]
        )

        let resolvedSwiftParserModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftParserModule,
            dependencies: [.module(resolvedSwiftSyntaxModule, conditions: [])]
        )

        let resolvedSwiftBasicFormatModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBasicFormatModule,
            dependencies: [.module(resolvedSwiftSyntaxModule, conditions: [])]
        )

        let resolvedSwiftOperatorsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftOperatorsModule,
            dependencies: [
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftSyntaxModule, conditions: []),
            ]
        )

        let resolvedSwiftParserDiagnosticsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftParserDiagnosticsModule,
            dependencies: [
                .module(resolvedSwiftBasicFormatModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftSyntaxModule, conditions: []),
            ]
        )

        let resolvedSwiftSyntaxBuilderModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxBuilderModule,
            dependencies: [
                .module(resolvedSwiftBasicFormatModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftParserDiagnosticsModule, conditions: []),
                .module(resolvedSwiftSyntaxModule, conditions: []),
            ]
        )

        let resolvedSwiftIDEUtilsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftIDEUtilsModule,
            dependencies: [
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
            ]
        )

        let resolvedSwiftIfConfigModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftIfConfigModule,
            dependencies: [
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftSyntaxBuilderModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftOperatorsModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
            ]
        )

        let resolvedSwiftLexicalLookupModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftLexicalLookupModule,
            dependencies: [
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftIfConfigModule, conditions: []),
            ]
        )

        let resolvedSwiftRefactorModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftRefactorModule,
            dependencies: [
                .module(resolvedSwiftBasicFormatModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftSyntaxBuilderModule, conditions: []),
            ]
        )

        let resolvedSwiftSyntaxMacrosModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxMacrosModule,
            dependencies: [
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftIfConfigModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftSyntaxBuilderModule, conditions: []),
            ]
        )

        let resolvedSwiftSyntaxMacroExpansionModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxMacroExpansionModule,
            dependencies: [
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftSyntaxBuilderModule, conditions: []),
                .module(resolvedSwiftSyntaxMacrosModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftOperatorsModule, conditions: []),
            ]
        )

        let resolvedSwiftCompilerPluginMessageHandlingModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftCompilerPluginMessageHandlingModule,
            dependencies: [
                .module(resolvedSwiftSyntaxCShimsModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftOperatorsModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftSyntaxMacrosModule, conditions: []),
                .module(resolvedSwiftSyntaxMacroExpansionModule, conditions: []),
            ]
        )

        let resolvedSwiftCompilerPluginModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftCompilerPluginModule,
            dependencies: [
                .module(resolvedSwiftCompilerPluginMessageHandlingModule, conditions: []),
                .module(resolvedSwiftSyntaxMacrosModule, conditions: []),
            ]
        )

        let resolvedSwiftLibraryPluginProviderModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftLibraryPluginProviderModule,
            dependencies: [
                .module(resolvedSwiftSyntaxMacrosModule, conditions: []),
                .module(resolvedSwiftCompilerPluginMessageHandlingModule, conditions: []),
                .module(resolvedSwiftLibraryPluginProviderCShimsModule, conditions: []),
            ]
        )

        let resolvedSwiftSyntaxMacrosGenericTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxMacrosGenericTestSupportModule,
            dependencies: [
                .module(resolvedSwiftSyntaxGenericTestSupportModule, conditions: []),
                .module(resolvedSwiftDiagnosticsModule, conditions: []),
                .module(resolvedSwiftIDEUtilsModule, conditions: []),
                .module(resolvedSwiftIfConfigModule, conditions: []),
                .module(resolvedSwiftParserModule, conditions: []),
                .module(resolvedSwiftSyntaxMacrosModule, conditions: []),
                .module(resolvedSwiftSyntaxMacroExpansionModule, conditions: []),
            ]
        )

        let resolvedSwiftSyntaxMacrosTestSupportModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSyntaxMacrosTestSupportModule,
            dependencies: [
                .module(resolvedSwiftSyntaxModule, conditions: []),
                .module(resolvedSwiftSyntaxMacroExpansionModule, conditions: []),
                .module(resolvedSwiftSyntaxMacrosModule, conditions: []),
                .module(resolvedSwiftSyntaxMacrosGenericTestSupportModule, conditions: []),
            ]
        )

        // MARK: - Create resolved products

        let resolvedSwiftSyntaxProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftSyntaxProduct,
            modules: IdentifiableSet([resolvedSwiftSyntaxModule])
        )
        let resolvedSwiftDiagnosticsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDiagnosticsProduct,
            modules: IdentifiableSet([resolvedSwiftDiagnosticsModule])
        )
        let resolvedSwiftParserProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftParserProduct,
            modules: IdentifiableSet([resolvedSwiftParserModule])
        )
        let resolvedSwiftBasicFormatProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftBasicFormatProduct,
            modules: IdentifiableSet([resolvedSwiftBasicFormatModule])
        )
        let resolvedSwiftOperatorsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftOperatorsProduct,
            modules: IdentifiableSet([resolvedSwiftOperatorsModule])
        )
        let resolvedSwiftParserDiagnosticsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftParserDiagnosticsProduct,
            modules: IdentifiableSet([resolvedSwiftParserDiagnosticsModule])
        )
        let resolvedSwiftSyntaxBuilderProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftSyntaxBuilderProduct,
            modules: IdentifiableSet([resolvedSwiftSyntaxBuilderModule])
        )
        let resolvedSwiftIDEUtilsProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftIDEUtilsProduct,
            modules: IdentifiableSet([resolvedSwiftIDEUtilsModule])
        )
        let resolvedSwiftIfConfigProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftIfConfigProduct,
            modules: IdentifiableSet([resolvedSwiftIfConfigModule])
        )
        let resolvedSwiftLexicalLookupProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftLexicalLookupProduct,
            modules: IdentifiableSet([resolvedSwiftLexicalLookupModule])
        )
        let resolvedSwiftRefactorProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftRefactorProduct,
            modules: IdentifiableSet([resolvedSwiftRefactorModule])
        )
        let resolvedSwiftSyntaxMacrosProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftSyntaxMacrosProduct,
            modules: IdentifiableSet([resolvedSwiftSyntaxMacrosModule])
        )
        let resolvedSwiftSyntaxMacroExpansionProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftSyntaxMacroExpansionProduct,
            modules: IdentifiableSet([resolvedSwiftSyntaxMacroExpansionModule])
        )
        let resolvedSwiftCompilerPluginProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftCompilerPluginProduct,
            modules: IdentifiableSet([resolvedSwiftCompilerPluginModule])
        )
        let resolvedSwiftCompilerPluginMessageHandlingProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftCompilerPluginMessageHandlingProduct,
            modules: IdentifiableSet([resolvedSwiftCompilerPluginMessageHandlingModule])
        )
        let resolvedSwiftLibraryPluginProviderProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftLibraryPluginProviderProduct,
            modules: IdentifiableSet([resolvedSwiftLibraryPluginProviderModule])
        )
        let resolvedSwiftSyntaxMacrosGenericTestSupportProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftSyntaxMacrosGenericTestSupportProduct,
            modules: IdentifiableSet([resolvedSwiftSyntaxMacrosGenericTestSupportModule])
        )
        let resolvedSwiftSyntaxMacrosTestSupportProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftSyntaxMacrosTestSupportProduct,
            modules: IdentifiableSet([resolvedSwiftSyntaxMacrosTestSupportModule])
        )

        // MARK: - Create resolved package

        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedSwiftSyntaxCShimsModule, resolvedSwiftSyntax509Module, resolvedSwiftSyntax510Module,
                resolvedSwiftSyntax600Module, resolvedSwiftSyntax601Module, resolvedSwiftSyntax602Module,
                resolvedSwiftSyntax603Module, resolvedSwiftSyntaxGenericTestSupportModule,
                resolvedSwiftLibraryPluginProviderCShimsModule,
                resolvedSwiftSyntaxModule, resolvedSwiftDiagnosticsModule, resolvedSwiftParserModule,
                resolvedSwiftBasicFormatModule, resolvedSwiftOperatorsModule, resolvedSwiftParserDiagnosticsModule,
                resolvedSwiftSyntaxBuilderModule, resolvedSwiftIDEUtilsModule, resolvedSwiftIfConfigModule,
                resolvedSwiftLexicalLookupModule, resolvedSwiftRefactorModule, resolvedSwiftSyntaxMacrosModule,
                resolvedSwiftSyntaxMacroExpansionModule, resolvedSwiftCompilerPluginMessageHandlingModule,
                resolvedSwiftCompilerPluginModule, resolvedSwiftLibraryPluginProviderModule,
                resolvedSwiftSyntaxMacrosGenericTestSupportModule, resolvedSwiftSyntaxMacrosTestSupportModule,
            ]),
            products: [
                resolvedSwiftSyntaxProduct, resolvedSwiftDiagnosticsProduct, resolvedSwiftParserProduct,
                resolvedSwiftBasicFormatProduct, resolvedSwiftOperatorsProduct, resolvedSwiftParserDiagnosticsProduct,
                resolvedSwiftSyntaxBuilderProduct, resolvedSwiftIDEUtilsProduct, resolvedSwiftIfConfigProduct,
                resolvedSwiftLexicalLookupProduct, resolvedSwiftRefactorProduct, resolvedSwiftSyntaxMacrosProduct,
                resolvedSwiftSyntaxMacroExpansionProduct, resolvedSwiftCompilerPluginProduct,
                resolvedSwiftCompilerPluginMessageHandlingProduct, resolvedSwiftLibraryPluginProviderProduct,
                resolvedSwiftSyntaxMacrosGenericTestSupportProduct, resolvedSwiftSyntaxMacrosTestSupportProduct,
            ]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-syntax.git"))
        )

        return (
            package: package,
            modules: [
                swiftSyntaxCShimsModule, swiftSyntax509Module, swiftSyntax510Module, swiftSyntax600Module,
                swiftSyntax601Module, swiftSyntax602Module, swiftSyntax603Module, swiftSyntaxGenericTestSupportModule,
                swiftLibraryPluginProviderCShimsModule, swiftSyntaxModule, swiftDiagnosticsModule, swiftParserModule,
                swiftBasicFormatModule, swiftOperatorsModule, swiftParserDiagnosticsModule, swiftSyntaxBuilderModule,
                swiftIDEUtilsModule, swiftIfConfigModule, swiftLexicalLookupModule, swiftRefactorModule,
                swiftSyntaxMacrosModule, swiftSyntaxMacroExpansionModule, swiftCompilerPluginMessageHandlingModule,
                swiftCompilerPluginModule, swiftLibraryPluginProviderModule, swiftSyntaxMacrosGenericTestSupportModule,
                swiftSyntaxMacrosTestSupportModule,
            ],
            products: [
                swiftSyntaxProduct, swiftDiagnosticsProduct, swiftParserProduct, swiftBasicFormatProduct,
                swiftOperatorsProduct, swiftParserDiagnosticsProduct, swiftSyntaxBuilderProduct, swiftIDEUtilsProduct,
                swiftIfConfigProduct, swiftLexicalLookupProduct, swiftRefactorProduct, swiftSyntaxMacrosProduct,
                swiftSyntaxMacroExpansionProduct, swiftCompilerPluginProduct, swiftCompilerPluginMessageHandlingProduct,
                swiftLibraryPluginProviderProduct, swiftSyntaxMacrosGenericTestSupportProduct,
                swiftSyntaxMacrosTestSupportProduct,
            ],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedSwiftSyntaxCShimsModule, resolvedSwiftSyntax509Module, resolvedSwiftSyntax510Module,
                resolvedSwiftSyntax600Module, resolvedSwiftSyntax601Module, resolvedSwiftSyntax602Module,
                resolvedSwiftSyntax603Module, resolvedSwiftSyntaxGenericTestSupportModule,
                resolvedSwiftLibraryPluginProviderCShimsModule,
                resolvedSwiftSyntaxModule, resolvedSwiftDiagnosticsModule, resolvedSwiftParserModule,
                resolvedSwiftBasicFormatModule, resolvedSwiftOperatorsModule, resolvedSwiftParserDiagnosticsModule,
                resolvedSwiftSyntaxBuilderModule, resolvedSwiftIDEUtilsModule, resolvedSwiftIfConfigModule,
                resolvedSwiftLexicalLookupModule, resolvedSwiftRefactorModule, resolvedSwiftSyntaxMacrosModule,
                resolvedSwiftSyntaxMacroExpansionModule, resolvedSwiftCompilerPluginMessageHandlingModule,
                resolvedSwiftCompilerPluginModule, resolvedSwiftLibraryPluginProviderModule,
                resolvedSwiftSyntaxMacrosGenericTestSupportModule, resolvedSwiftSyntaxMacrosTestSupportModule,
            ],
            resolvedProducts: [
                resolvedSwiftSyntaxProduct, resolvedSwiftDiagnosticsProduct, resolvedSwiftParserProduct,
                resolvedSwiftBasicFormatProduct, resolvedSwiftOperatorsProduct, resolvedSwiftParserDiagnosticsProduct,
                resolvedSwiftSyntaxBuilderProduct, resolvedSwiftIDEUtilsProduct, resolvedSwiftIfConfigProduct,
                resolvedSwiftLexicalLookupProduct, resolvedSwiftRefactorProduct, resolvedSwiftSyntaxMacrosProduct,
                resolvedSwiftSyntaxMacroExpansionProduct, resolvedSwiftCompilerPluginProduct,
                resolvedSwiftCompilerPluginMessageHandlingProduct, resolvedSwiftLibraryPluginProviderProduct,
                resolvedSwiftSyntaxMacrosGenericTestSupportProduct, resolvedSwiftSyntaxMacrosTestSupportProduct,
            ],
            packageRef: packageRef
        )
    }
}
