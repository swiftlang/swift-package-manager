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
struct SBOMExtractCategoryTests {
    // MARK: - Product Category Tests

    struct ProductCategoryTestCase {
        let productType: ProductType
        let moduleType: Module.Kind
        let expectedCategory: SBOMComponent.Category
        let description: String
    }

    static let productCategoryTestCases: [ProductCategoryTestCase] = [
        ProductCategoryTestCase(
            productType: .executable,
            moduleType: .executable,
            expectedCategory: .application,
            description: "executable"
        ),
        ProductCategoryTestCase(
            productType: .library(.automatic),
            moduleType: .library,
            expectedCategory: .library,
            description: "library"
        ),
        ProductCategoryTestCase(
            productType: .test,
            moduleType: .test,
            expectedCategory: .library,
            description: "test"
        ),
        ProductCategoryTestCase(
            productType: .snippet,
            moduleType: .library,
            expectedCategory: .library,
            description: "snippet"
        ),
        ProductCategoryTestCase(
            productType: .plugin,
            moduleType: .library,
            expectedCategory: .library,
            description: "plugin"
        ),
        ProductCategoryTestCase(
            productType: .macro,
            moduleType: .library,
            expectedCategory: .library,
            description: "macro"
        ),
    ]

    @Test("extractCategoryFromProduct", arguments: productCategoryTestCases)
    func extractCategoryFromProduct(testCase: ProductCategoryTestCase) throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyProduct",
            type: testCase.productType,
            moduleType: testCase.moduleType
        )
        let category = try SBOMExtractor.extractCategory(from: resolvedProduct)
        #expect(category == testCase.expectedCategory)
    }

    // MARK: - Package Category Tests

    struct PackageCategoryTestCase {
        let productTypes: [(ProductType, Module.Kind?)]
        let expectedCategory: SBOMComponent.Category
        let description: String
    }

    static let packageCategoryTestCases: [PackageCategoryTestCase] = [
        PackageCategoryTestCase(
            productTypes: [(.executable, .executable)],
            expectedCategory: .application,
            description: "executable product"
        ),
        PackageCategoryTestCase(
            productTypes: [(.library(.automatic), nil), (.library(.dynamic), nil)],
            expectedCategory: .library,
            description: "only library products"
        ),
        PackageCategoryTestCase(
            productTypes: [(.library(.automatic), nil), (.executable, .executable)],
            expectedCategory: .application,
            description: "mixed products with executable"
        ),
        PackageCategoryTestCase(
            productTypes: [(.test, .test)],
            expectedCategory: .library,
            description: "test product"
        ),
        PackageCategoryTestCase(
            productTypes: [(.snippet, nil)],
            expectedCategory: .library,
            description: "snippet product"
        ),
        PackageCategoryTestCase(
            productTypes: [(.plugin, nil)],
            expectedCategory: .library,
            description: "plugin product"
        ),
        PackageCategoryTestCase(
            productTypes: [(.macro, nil)],
            expectedCategory: .library,
            description: "macro product"
        ),
        PackageCategoryTestCase(
            productTypes: [(.executable, .executable), (.executable, .executable)],
            expectedCategory: .application,
            description: "multiple executables"
        ),
        PackageCategoryTestCase(
            productTypes: [(.library(.automatic), nil), (.executable, .executable), (.test, .test), (.plugin, nil)],
            expectedCategory: .application,
            description: "all product types with executable"
        ),
    ]

    @Test("extractCategoryFromPackage", arguments: packageCategoryTestCases)
    func extractCategoryFromPackage(testCase: PackageCategoryTestCase) throws {
        var products: [ResolvedProduct] = []
        for (index, (productType, moduleType)) in testCase.productTypes.enumerated() {
            let product = try SBOMTestModulesGraph.createProduct(
                name: "Product\(index)",
                type: productType,
                moduleType: moduleType ?? .library
            )
            products.append(product)
        }

        let resolvedPackage = try SBOMTestModulesGraph.createPackage(
            name: "TestPackage",
            products: products
        )
        let category = try SBOMExtractor.extractCategory(from: resolvedPackage)
        #expect(category == testCase.expectedCategory)
    }
}
