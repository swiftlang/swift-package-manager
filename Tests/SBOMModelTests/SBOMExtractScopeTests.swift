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
        .Feature.SBOM
    )
)
struct SBOMExtractScopeTests {
    @Test("extractScopeFromProduct with executable product returns runtime")
    func extractScopeFromExecutableProduct() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyExecutableProduct",
            type: .executable,
            moduleType: .executable
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedProduct)
        #expect(scope == SBOMComponent.Scope.runtime)
    }

    @Test("extractScopeFromProduct with library product returns runtime")
    func extractScopeFromLibraryProduct() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyLibraryProduct",
            type: .library(.automatic)
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedProduct)
        #expect(scope == SBOMComponent.Scope.runtime)
    }

    @Test("extractScopeFromProduct with test product returns test")
    func extractScopeFromTestProduct() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyTestProduct",
            type: .test,
            moduleType: .test
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedProduct)
        #expect(scope == SBOMComponent.Scope.test)
    }

    @Test("extractScopeFromProduct with library product containing only test module returns test")
    func extractScopeFromLibraryProductWithTestModule() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyLibraryProduct",
            type: .library(.automatic),
            moduleType: .test
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedProduct)
        #expect(scope == SBOMComponent.Scope.test)
    }

    @Test("extractScopeFromPackage with executable product returns runtime")
    func extractScopeFromPackageWithExecutable() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyExecutableProduct",
            type: .executable,
            moduleType: .executable
        )
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(name: "Executable", products: [resolvedProduct])
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == SBOMComponent.Scope.runtime)
    }

    @Test("extractScopeFromPackage with library product returns runtime")
    func extractScopeFromPackageWithLibrary() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyLibraryProduct",
            type: .library(.automatic)
        )
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(name: "Library", products: [resolvedProduct])
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == SBOMComponent.Scope.runtime)
    }

    @Test("extractScopeFromPackage with test product returns test")
    func extractScopeFromPackageWithTestProduct() throws {
        let resolvedProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyTestProduct",
            type: .test,
            moduleType: .test
        )
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(name: "TestPackage", products: [resolvedProduct])
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == SBOMComponent.Scope.test)
    }

    @Test("extractScopeFromPackage with mixed products containing test returns runtime")
    func extractScopeFromPackageWithMixedProductsIncludingTest() throws {
        let executableProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyExecutableProduct",
            type: .executable,
            moduleType: .executable
        )
        let testProduct = try SBOMTestModulesGraph.createProduct(name: "MyTestProduct", type: .test, moduleType: .test)
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(
            name: "MixedPackage",
            products: [executableProduct, testProduct]
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == SBOMComponent.Scope.runtime)
    }

    @Test("extractScopeFromPackage with test module but no test product returns test")
    func extractScopeFromPackageWithTestModule() throws {
        let libraryProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyLibraryProduct",
            type: .library(.automatic)
        )
        let testModule = SBOMTestModulesGraph.createSwiftModule(name: "TestModule", type: .test)
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(
            name: "PackageWithTests",
            products: [libraryProduct],
            modules: [testModule]
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == SBOMComponent.Scope.runtime)
    }

    @Test("extractScopeFromPackage with only runtime products and modules returns runtime")
    func extractScopeFromPackageWithOnlyRuntimeComponents() throws {
        let executableProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyExecutableProduct",
            type: .executable,
            moduleType: .executable
        )
        let libraryProduct = try SBOMTestModulesGraph.createProduct(
            name: "MyLibraryProduct",
            type: .library(.automatic)
        )
        let resolvedPackage = try SBOMTestModulesGraph.createPackage(
            name: "RuntimePackage",
            products: [executableProduct, libraryProduct]
        )
        let scope = try SBOMExtractor.extractScope(from: resolvedPackage)
        #expect(scope == SBOMComponent.Scope.runtime)
    }
}
