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
import Testing

@Suite(
    .tags(
        .Feature.SBOM,
        .TestSize.small
    )
)
struct SBOMExtractScopeTests {
    struct ProductScopeTestCase {
        let productType: ProductType
        let moduleType: Module.Kind
        let expectedScope: SBOMComponent.Scope
        let description: String
    }

    static let productScopeTestCases: [ProductScopeTestCase] = [
        ProductScopeTestCase(
            productType: .executable,
            moduleType: .executable,
            expectedScope: .runtime,
            description: "executable"
        ),
        ProductScopeTestCase(
            productType: .library(.automatic),
            moduleType: .library,
            expectedScope: .runtime,
            description: "library"
        ),
        ProductScopeTestCase(
            productType: .test,
            moduleType: .test,
            expectedScope: .test,
            description: "test"
        ),
        ProductScopeTestCase(
            productType: .library(.automatic),
            moduleType: .test,
            expectedScope: .test,
            description: "library with test module"
        ),
    ]

    @Test("extractScopeFromProduct", arguments: productScopeTestCases)
    func extractScopeFromProduct(testCase: ProductScopeTestCase) throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyProduct",
            type: testCase.productType,
            moduleType: testCase.moduleType
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedProduct)
        #expect(scope == testCase.expectedScope)
    }

    struct PackageScopeTestCase {
        let productTypes: [(ProductType, Module.Kind?)]
        let additionalModules: [Module.Kind]
        let expectedScope: SBOMComponent.Scope
        let description: String
    }

    static let packageScopeTestCases: [PackageScopeTestCase] = [
        PackageScopeTestCase(
            productTypes: [(.executable, .executable)],
            additionalModules: [],
            expectedScope: .runtime,
            description: "executable product"
        ),
        PackageScopeTestCase(
            productTypes: [(.library(.automatic), nil)],
            additionalModules: [],
            expectedScope: .runtime,
            description: "library product"
        ),
        PackageScopeTestCase(
            productTypes: [(.test, .test)],
            additionalModules: [],
            expectedScope: .test,
            description: "test product"
        ),
        PackageScopeTestCase(
            productTypes: [(.executable, .executable), (.test, .test)],
            additionalModules: [],
            expectedScope: .runtime,
            description: "mixed products with test"
        ),
        PackageScopeTestCase(
            productTypes: [(.library(.automatic), nil)],
            additionalModules: [.test],
            expectedScope: .runtime,
            description: "test module but no test product"
        ),
        PackageScopeTestCase(
            productTypes: [(.executable, .executable), (.library(.automatic), nil)],
            additionalModules: [],
            expectedScope: .runtime,
            description: "only runtime products and modules"
        ),
    ]

    @Test("extractScopeFromPackage", arguments: packageScopeTestCases)
    func extractScopeFromPackage(testCase: PackageScopeTestCase) throws {
        var products: [ResolvedProduct] = []
        for (index, (productType, moduleType)) in testCase.productTypes.enumerated() {
            let product = try SBOMTestModulesGraph.createProduct(
                name: "Product\(index)",
                type: productType,
                moduleType: moduleType ?? .library
            )
            products.append(product)
        }
        
        var modules: [Module] = []
        for (index, moduleType) in testCase.additionalModules.enumerated() {
            let module = SBOMTestModulesGraph.createSwiftModule(
                name: "AdditionalModule\(index)",
                type: moduleType
            )
            modules.append(module)
        }
        
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(
            name: "TestPackage",
            products: products,
            modules: modules
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == testCase.expectedScope)
    }
}
