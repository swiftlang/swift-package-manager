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
    static func createSimpleModulesGraph(rootPath: String = "/tmp/simple-mock") throws -> ModulesGraph {
        // - MyApp package depends on Utils package and App product
        // - Utils package depends on Utils product
        // - App product depends on Utils product

        // Package identities
        let appIdentity = PackageIdentity.plain("MyApp")
        let utilsIdentity = PackageIdentity.plain("Utils")

        // Create modules for Utils package (dependency)
        let utilsModule = self.createSwiftModule(name: "Utils")

        // Create modules for MyApp package (root)
        let appModule = self.createSwiftModule(name: "App", type: .executable)

        // Create products
        let utilsProduct = try Product(
            package: utilsIdentity,
            name: "Utils",
            type: .library(.automatic),
            modules: [utilsModule]
        )

        let appProduct = try Product(
            package: appIdentity,
            name: "App",
            type: .executable,
            modules: [appModule]
        )

        // Create packages
        let utilsPackage = self.createPackage(
            identity: utilsIdentity,
            displayName: "Utils",
            path: "/Utils",
            modules: [utilsModule],
            products: [utilsProduct]
        )

        let appPackage = self.createPackage(
            identity: appIdentity,
            displayName: "MyApp",
            path: rootPath,
            modules: [appModule],
            products: [appProduct]
        )

        // Create resolved modules
        let resolvedUtilsModule = self.createResolvedModule(
            packageIdentity: utilsIdentity,
            module: utilsModule
        )

        let resolvedAppModule = self.createResolvedModule(
            packageIdentity: appIdentity,
            module: appModule,
            dependencies: [
                .product(self.createResolvedProduct(
                    packageIdentity: utilsIdentity,
                    product: utilsProduct,
                    modules: IdentifiableSet([resolvedUtilsModule])
                ), conditions: []),
            ]
        )

        // Create resolved products
        let resolvedUtilsProduct = self.createResolvedProduct(
            packageIdentity: utilsIdentity,
            product: utilsProduct,
            modules: IdentifiableSet([resolvedUtilsModule])
        )

        let resolvedAppProduct = self.createResolvedProduct(
            packageIdentity: appIdentity,
            product: appProduct,
            modules: IdentifiableSet([resolvedAppModule])
        )

        // Create resolved packages
        let resolvedUtilsPackage = self.createResolvedPackage(
            package: utilsPackage,
            modules: IdentifiableSet([resolvedUtilsModule]),
            products: [resolvedUtilsProduct]
        )

        let resolvedAppPackage = self.createResolvedPackage(
            package: appPackage,
            modules: IdentifiableSet([resolvedAppModule]),
            products: [resolvedAppProduct],
            dependencies: [utilsIdentity]
        )

        // Create package references
        let utilsRef = PackageReference(
            identity: utilsIdentity,
            kind: .remoteSourceControl(SourceControlURL("https://github.com/example/utils.git"))
        )

        // Create the ModulesGraph
        return try ModulesGraph(
            rootPackages: [resolvedAppPackage],
            rootDependencies: [resolvedUtilsPackage],
            packages: IdentifiableSet([resolvedAppPackage, resolvedUtilsPackage]),
            dependencies: [utilsRef],
            binaryArtifacts: [:]
        )
    }
}
