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
    // MARK: - swift-docc-symbolkit Package

    static func createSPMSwiftDoccSymbolKitPackage() throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-docc-symbolkit")

        // Modules
        let symbolKitModule = self.createSwiftModule(name: "SymbolKit")

        // Products
        let symbolKitProduct = try Product(
            package: identity,
            name: "SymbolKit",
            type: .library(.automatic),
            modules: [symbolKitModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "SymbolKit",
            path: "/swift-docc-symbolkit",
            modules: [symbolKitModule],
            products: [symbolKitProduct]
        )

        // Resolved modules
        let resolvedSymbolKitModule = self.createResolvedModule(
            packageIdentity: identity,
            module: symbolKitModule
        )

        // Resolved products
        let resolvedSymbolKitProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: symbolKitProduct,
            modules: IdentifiableSet([resolvedSymbolKitModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([resolvedSymbolKitModule]),
            products: [resolvedSymbolKitProduct]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-docc-symbolkit"))
        )

        return (
            package: package,
            modules: [symbolKitModule],
            products: [symbolKitProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [resolvedSymbolKitModule],
            resolvedProducts: [resolvedSymbolKitProduct],
            packageRef: packageRef
        )
    }

    // MARK: - swift-docc-plugin Package

    static func createSPMSwiftDoccPluginPackage(
        symbolKitProduct: ResolvedProduct
    ) throws -> (
        package: Package,
        modules: [Module],
        products: [Product],
        resolvedPackage: ResolvedPackage,
        resolvedModules: [ResolvedModule],
        resolvedProducts: [ResolvedProduct],
        packageRef: PackageReference
    ) {
        let identity = PackageIdentity.plain("swift-docc-plugin")

        // Modules
        let snippetsModule = self.createSwiftModule(name: "Snippets")
        let snippetExtractModule = self.createSwiftModule(name: "snippet-extract", type: .executable)
        let swiftDoccModule = self.createSwiftModule(name: "Swift-DocC", type: .plugin)
        let swiftDoccPreviewModule = self.createSwiftModule(name: "Swift-DocC Preview", type: .plugin)

        // Products
        let snippetExtractProduct = try Product(
            package: identity,
            name: "snippet-extract",
            type: .executable,
            modules: [snippetExtractModule]
        )

        let swiftDoccProduct = try Product(
            package: identity,
            name: "Swift-DocC",
            type: .plugin,
            modules: [swiftDoccModule]
        )

        let swiftDoccPreviewProduct = try Product(
            package: identity,
            name: "Swift-DocC Preview",
            type: .plugin,
            modules: [swiftDoccPreviewModule]
        )

        // Package
        let package = self.createPackage(
            identity: identity,
            displayName: "SwiftDocCPlugin",
            path: "/swift-docc-plugin",
            modules: [snippetsModule, snippetExtractModule, swiftDoccModule, swiftDoccPreviewModule],
            products: [snippetExtractProduct, swiftDoccProduct, swiftDoccPreviewProduct]
        )

        // Resolved modules
        let resolvedSnippetsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: snippetsModule
        )

        let resolvedSnippetExtractModule = self.createResolvedModule(
            packageIdentity: identity,
            module: snippetExtractModule,
            dependencies: [
                .module(resolvedSnippetsModule, conditions: []),
                .product(symbolKitProduct, conditions: []),
            ]
        )

        let resolvedSwiftDoccModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftDoccModule,
            dependencies: [
                .module(resolvedSnippetExtractModule, conditions: []),
            ]
        )

        let resolvedSwiftDoccPreviewModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftDoccPreviewModule,
            dependencies: [
                .module(resolvedSnippetExtractModule, conditions: []),
            ]
        )

        // Resolved products
        let resolvedSnippetExtractProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: snippetExtractProduct,
            modules: IdentifiableSet([resolvedSnippetExtractModule])
        )

        let resolvedSwiftDoccProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDoccProduct,
            modules: IdentifiableSet([resolvedSwiftDoccModule])
        )

        let resolvedSwiftDoccPreviewProduct = self.createResolvedProduct(
            packageIdentity: identity,
            product: swiftDoccPreviewProduct,
            modules: IdentifiableSet([resolvedSwiftDoccPreviewModule])
        )

        // Resolved package
        let resolvedPackage = self.createResolvedPackage(
            package: package,
            modules: IdentifiableSet([
                resolvedSnippetsModule, resolvedSnippetExtractModule,
                resolvedSwiftDoccModule, resolvedSwiftDoccPreviewModule,
            ]),
            products: [
                resolvedSnippetExtractProduct, resolvedSwiftDoccProduct, resolvedSwiftDoccPreviewProduct,
            ],
            dependencies: [PackageIdentity.plain("swift-docc-symbolkit")]
        )

        // Package reference
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/swiftlang/swift-docc-plugin"))
        )

        return (
            package: package,
            modules: [snippetsModule, snippetExtractModule, swiftDoccModule, swiftDoccPreviewModule],
            products: [snippetExtractProduct, swiftDoccProduct, swiftDoccPreviewProduct],
            resolvedPackage: resolvedPackage,
            resolvedModules: [
                resolvedSnippetsModule, resolvedSnippetExtractModule,
                resolvedSwiftDoccModule, resolvedSwiftDoccPreviewModule,
            ],
            resolvedProducts: [
                resolvedSnippetExtractProduct, resolvedSwiftDoccProduct, resolvedSwiftDoccPreviewProduct,
            ],
            packageRef: packageRef
        )
    }
}
