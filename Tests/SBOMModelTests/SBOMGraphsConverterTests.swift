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
import Foundation
import PackageGraph
@testable import SBOMModel
import Testing

@Suite(
    .tags(
        .Feature.SBOM,
        .TestSize.medium
    )
)
struct SBOMGraphsConverterTests {
    
    // MARK: - toProduct and toModule Tests
    // Note: Basic name mapping tests (getTargetName, getProductName, getModuleName) have been
    // moved to Tests/SwiftBuildSupportTests/PackagePIFBuilderHelpersTests.swift to test the
    // underlying PackagePIFBuilder functions directly.

    @Test("toProduct(fromTarget:) returns correct product for valid product targets")
    func toProductWithValidTargets() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        let swiftlyProduct = SBOMGraphsConverter.toProduct(fromTarget: "swiftly-product", modulesGraph: graph)
        #expect(swiftlyProduct?.name == "swiftly", "Product name should be 'swiftly'")

        let testSwiftlyProduct = SBOMGraphsConverter.toProduct(fromTarget: "test-swiftly-product", modulesGraph: graph)
        #expect(testSwiftlyProduct?.name == "test-swiftly", "Product name should be 'test-swiftly'")
    }

    @Test("toProduct(fromTarget:) returns nil for non-product targets")
    func toProductWithNonProductTargets() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        #expect(SBOMGraphsConverter.toProduct(fromTarget: "Swiftly", modulesGraph: graph) == nil, "Module name should not be recognized as product")
        #expect(
            SBOMGraphsConverter.toProduct(fromTarget: "SwiftlyCore", modulesGraph: graph) == nil,
            "Module name should not be recognized as product"
        )
        #expect(
            SBOMGraphsConverter.toProduct(fromTarget: "_AsyncFileSystem", modulesGraph: graph) == nil,
            "Module with underscore should not be recognized as product"
        )
        #expect(SBOMGraphsConverter.toProduct(fromTarget: "SPMSQLite3", modulesGraph: graph) == nil, "Module name should not be recognized as product")

        #expect(
            SBOMGraphsConverter.toProduct(fromTarget: "swift-nio_NIOPosix", modulesGraph: graph) == nil,
            "Package_module format should not be recognized as product"
        )
        #expect(
            SBOMGraphsConverter.toProduct(fromTarget: "swift-nio__NIOBase64", modulesGraph: graph) == nil,
            "Package_module with underscore should not be recognized as product"
        )
    }

    @Test("toProduct(fromTarget:) handles edge cases for product targets")
    func toProductEdgeCases() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()

        let swiftBuildProduct = SBOMGraphsConverter.toProduct(fromTarget: "SwiftBuild-product", modulesGraph: graph)
        #expect(swiftBuildProduct != nil, "SwiftBuild-product should exist in modules graph")

        let swbBuildServiceProduct = SBOMGraphsConverter.toProduct(fromTarget: "SWBBuildService-product", modulesGraph: graph)
        #expect(swbBuildServiceProduct != nil, "SWBBuildService-product should exist in modules graph")
    }

    @Test("toModule(fromTarget:) returns correct module for simple module names")
    func toModuleWithSimpleNames() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        let swiftlyModule = SBOMGraphsConverter.toModule(fromTarget: "Swiftly", modulesGraph: graph)
        #expect(swiftlyModule?.name == "Swiftly", "Module name should be 'Swiftly'")

        let swiftlyCoreModule = SBOMGraphsConverter.toModule(fromTarget: "SwiftlyCore", modulesGraph: graph)
        #expect(swiftlyCoreModule?.name == "SwiftlyCore", "Module name should be 'SwiftlyCore'")
    }

    @Test("toModule(fromTarget:) returns correct module for system module")
    func toModuleWithSystemModules() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()

        let spmSQLite3Module = SBOMGraphsConverter.toModule(fromTarget: "SPMSQLite3", modulesGraph: graph)
        #expect(spmSQLite3Module?.name == "SPMSQLite3", "Module name should be 'SPMSQLite3'")
    }

    @Test("toModule(fromTarget:) returns correct module for modules with leading underscores")
    func toModuleWithLeadingUnderscores() async throws {
        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()

        let asyncFileSystemModule = SBOMGraphsConverter.toModule(fromTarget: "_AsyncFileSystem", modulesGraph: graph)
        #expect(asyncFileSystemModule?.name == "_AsyncFileSystem", "Module name should be '_AsyncFileSystem'")

        let certificateInternalsModule = SBOMGraphsConverter.toModule(fromTarget: "_CertificateInternals", modulesGraph: graph)
        #expect(
            certificateInternalsModule?.name == "_CertificateInternals",
            "Module name should be '_CertificateInternals'"
        )

        let cryptoExtrasModule = SBOMGraphsConverter.toModule(fromTarget: "_CryptoExtras", modulesGraph: graph)
        #expect(cryptoExtrasModule?.name == "_CryptoExtras", "Module name should be '_CryptoExtras'")

        let swiftSyntaxCShimsModule = SBOMGraphsConverter.toModule(fromTarget: "_SwiftSyntaxCShims", modulesGraph: graph)
        #expect(swiftSyntaxCShimsModule?.name == "_SwiftSyntaxCShims", "Module name should be '_SwiftSyntaxCShims'")

        let swiftlyGraph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        let subprocessCShimsModule = SBOMGraphsConverter.toModule(fromTarget: "_SubprocessCShims", modulesGraph: swiftlyGraph)
        #expect(subprocessCShimsModule?.name == "_SubprocessCShims", "Module name should be '_SubprocessCShims'")
    }

    @Test("toModule(fromTarget:) returns nil for package_module format (because they're resource bundles)")
    func toModuleWithPackageModuleFormat() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        let nioPosixModule = SBOMGraphsConverter.toModule(fromTarget: "swift-nio_NIOPosix", modulesGraph: graph)
        #expect(nioPosixModule == nil)

        let nioSSLModule = SBOMGraphsConverter.toModule(fromTarget: "swift-nio-ssl_NIOSSL", modulesGraph: graph)
        #expect(nioSSLModule == nil)

        // Test modules with leading underscores in package_module format
        let nioBase64Module = SBOMGraphsConverter.toModule(fromTarget: "swift-nio__NIOBase64", modulesGraph: graph)
        #expect(nioBase64Module == nil)

        let nioDataStructuresModule = SBOMGraphsConverter.toModule(fromTarget: "swift-nio__NIODataStructures", modulesGraph: graph)
        #expect(nioDataStructuresModule == nil)

        let cryptoExtrasModule = SBOMGraphsConverter.toModule(fromTarget: "swift-crypto__CryptoExtras", modulesGraph: graph)
        #expect(cryptoExtrasModule == nil)
    }

    @Test("toModule(fromTarget:) returns nil for product targets")
    func toModuleWithProductTargets() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        #expect(
            SBOMGraphsConverter.toModule(fromTarget: "swiftly-product", modulesGraph: graph) == nil,
            "Product target should not be recognized as module"
        )
        #expect(
            SBOMGraphsConverter.toModule(fromTarget: "test-swiftly-product", modulesGraph: graph) == nil,
            "Product target should not be recognized as module"
        )
        #expect(
            SBOMGraphsConverter.toModule(fromTarget: "SwiftBuild-product", modulesGraph: graph) == nil,
            "Product target should not be recognized as module"
        )
        #expect(
            SBOMGraphsConverter.toModule(fromTarget: "SWBBuildService-product", modulesGraph: graph) == nil,
            "Product target should not be recognized as module"
        )
    }

    @Test("toModule(fromTarget:) handles non-existent modules gracefully")
    func toModuleWithNonExistentModules() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()

        #expect(SBOMGraphsConverter.toModule(fromTarget: "NonExistentModule", modulesGraph: graph) == nil, "Non-existent module should return nil")
        #expect(
            SBOMGraphsConverter.toModule(fromTarget: "_NonExistentModule", modulesGraph: graph) == nil,
            "Non-existent module with underscore should return nil"
        )
        #expect(
            SBOMGraphsConverter.toModule(fromTarget: "package_NonExistentModule", modulesGraph: graph) == nil,
            "Non-existent package_module should return nil"
        )
    }

    @Test("toProduct and toModule are mutually exclusive")
    func toProductAndToModuleMutualExclusivity() async throws {
        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()

        // Product targets should only work with toProduct
        let productTarget = "swiftly-product"
        #expect(SBOMGraphsConverter.toProduct(fromTarget: productTarget, modulesGraph: graph) != nil, "Product target should work with toProduct")
        #expect(SBOMGraphsConverter.toModule(fromTarget: productTarget, modulesGraph: graph) == nil, "Product target should not work with toModule")

        // Module targets should only work with toModule
        let moduleTarget = "Swiftly"
        #expect(SBOMGraphsConverter.toModule(fromTarget: moduleTarget, modulesGraph: graph) != nil, "Module target should work with toModule")
        #expect(SBOMGraphsConverter.toProduct(fromTarget: moduleTarget, modulesGraph: graph) == nil, "Module target should not work with toProduct")

        // Package_module format should only work with toModule
        let packageModuleTarget = "swift-nio_NIOPosix"
        if SBOMGraphsConverter.toModule(fromTarget: packageModuleTarget, modulesGraph: graph) != nil {
            #expect(
                SBOMGraphsConverter.toProduct(fromTarget: packageModuleTarget, modulesGraph: graph) == nil,
                "Package_module format should not work with toProduct"
            )
        }
    }
}