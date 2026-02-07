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

struct SBOMGraphsConverterTests {
    
    // MARK: - Name Mapping Tests

    @Test("getTargetName(fromProduct:) converts product names correctly")
    func getTargetNameFromProduct() {
        // Test with various product names from Swiftly graph
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "swiftly") == "swiftly-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "test-swiftly") == "test-swiftly-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "ArgumentParser") == "ArgumentParser-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "AsyncHTTPClient") == "AsyncHTTPClient-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "OpenAPIRuntime") == "OpenAPIRuntime-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "SystemPackage") == "SystemPackage-product")

        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "") == "-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "A") == "A-product")
        #expect(SBOMGraphsConverter.getTargetName(fromProduct: "product") == "product-product")
    }

    @Test("getProductName(fromTarget:) converts target names correctly")
    func getProductNameFromTarget() {
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "swiftly-product") == "swiftly")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "test-swiftly-product") == "test-swiftly")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "ArgumentParser-product") == "ArgumentParser")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "AsyncHTTPClient-product") == "AsyncHTTPClient")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "OpenAPIRuntime-product") == "OpenAPIRuntime")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "SystemPackage-product") == "SystemPackage")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "SwiftBuild-product") == "SwiftBuild")

        #expect(SBOMGraphsConverter.getProductName(fromTarget: "Swiftly") == nil)
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "TestSwiftly") == nil)
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "ArgumentParser") == nil)
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "SwiftlyCore") == nil)
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "MacOSPlatform") == nil)

        #expect(SBOMGraphsConverter.getProductName(fromTarget: "-product") == "")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "") == nil)
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "product") == nil)
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "my-product-product") == "my-product")
    }

    @Test("getProductName(fromTarget:) removes TargetSuffix patterns correctly")
    func getProductNameRemovesSuffixes() {
        // Test -dynamic suffix removal from PACKAGE-PRODUCT GUIDs
        // PACKAGE-PRODUCT:swift-build_SwiftBuild.SwiftBuild-6FA70E1059D35307-dynamic
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "SwiftBuild-dynamic-product") == "SwiftBuild")
        
        // PACKAGE-PRODUCT:swift-build_SWBProtocol.SWBProtocol-479FEB9464127B49-dynamic
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "SWBProtocol-dynamic-product") == "SWBProtocol")
        
        // Test -testable suffix removal
        // snippet-extract-4D525650E9464C3A-testable
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "snippet-extract-testable-product") == "snippet-extract")
        
        // swift-run--4E81F76B4FDE3E48-testable
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "swift-run-testable-product") == "swift-run")
        
        // swift-experimental-sdk--453A89A57E5CD913-testable
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "swift-experimental-sdk-testable-product") == "swift-experimental-sdk")
        
        // swift-bootstrap-19E6669016298B47-testable
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "swift-bootstrap-testable-product") == "swift-bootstrap")
        
        // Test products without suffixes
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "SwiftBuild-product") == "SwiftBuild")
        #expect(SBOMGraphsConverter.getProductName(fromTarget: "ArgumentParser-product") == "ArgumentParser")
    }

    @Test("getModuleName(fromTarget:) converts target names correctly")
    func getModuleNameFromTarget() {
        // Test simple module names (no package prefix)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "Swiftly") == "Swiftly")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "TestSwiftly") == "TestSwiftly")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "ArgumentParser") == "ArgumentParser")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SwiftlyCore") == "SwiftlyCore")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "MacOSPlatform") == "MacOSPlatform")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "LinuxPlatform") == "LinuxPlatform")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SwiftlyWebsiteAPI") == "SwiftlyWebsiteAPI")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SwiftlyDownloadAPI") == "SwiftlyDownloadAPI")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "AsyncHTTPClient") == "AsyncHTTPClient")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "OpenAPIRuntime") == "OpenAPIRuntime")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SPMSQLite3") == "SPMSQLite3")

        // Modules that start with underscores
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "_CryptoExtras") == "_CryptoExtras")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "_AsyncFileSystem") == "_AsyncFileSystem")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "_CertificateInternals") == "_CertificateInternals")

        // Test product names (should return nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swiftly-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "test-swiftly-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "ArgumentParser-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "AsyncHTTPClient-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "OpenAPIRuntime-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SystemPackage-product") == nil)

        // Test edge cases
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "") == "")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "A") == "A")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "my-product-product") == nil)

        // Test resource bundle package_module target format (with underscores)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-nio_NIOPosix") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-nio-ssl_NIOSSL") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-crypto_Crypto") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-crypto__CryptoExtras") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-nio__NIOBase64") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-nio__NIODataStructures") == nil)

        // Test modules with multiple leading underscores
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "___ModuleName") == "___ModuleName")
    }

    @Test("getModuleName(fromTarget:) removes TargetSuffix patterns correctly")
    func getModuleNameRemovesSuffixes() {
        // Test -dynamic suffix removal from PACKAGE-TARGET GUIDs
        // PACKAGE-TARGET:SWBTaskConstruction--13A05A6A6704C663-dynamic
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SWBTaskConstruction-dynamic") == "SWBTaskConstruction")
        
        // PACKAGE-TARGET:_IntegrationTestSupport-1FB010E086040497-dynamic
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "_IntegrationTestSupport-dynamic") == "_IntegrationTestSupport")
        
        // PACKAGE-TARGET:_AsyncFileSystem--4E4E671E738B868E-dynamic
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "_AsyncFileSystem-dynamic") == "_AsyncFileSystem")
        
        // PACKAGE-TARGET:PackageSigning--7F242844F5C56277-dynamic
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "PackageSigning-dynamic") == "PackageSigning")
        
        // Test -testable suffix removal
        // snippet-extract-4D525650E9464C3A-testable
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "snippet-extract-testable") == "snippet-extract")
        
        // swift-run--4E81F76B4FDE3E48-testable
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-run-testable") == "swift-run")
        
        // swift-experimental-sdk--453A89A57E5CD913-testable
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-experimental-sdk-testable") == "swift-experimental-sdk")
        
        // swift-bootstrap-19E6669016298B47-testable
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-bootstrap-testable") == "swift-bootstrap")
        
        // Test modules without suffixes
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SwiftBuild") == "SwiftBuild")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "_AsyncFileSystem") == "_AsyncFileSystem")
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "ArgumentParser") == "ArgumentParser")
        
        // Test that product targets still return nil even with suffixes
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "SwiftBuild-dynamic-product") == nil)
        #expect(SBOMGraphsConverter.getModuleName(fromTarget: "swift-run-testable-product") == nil)
    }

    @Test("name mapping functions are inverses for products")
    func productNameMappingRoundTrip() {
        let productNames = ["swiftly", "test-swiftly", "ArgumentParser", "AsyncHTTPClient", "OpenAPIRuntime"]

        for productName in productNames {
            let targetName = SBOMGraphsConverter.getTargetName(fromProduct: productName)
            let recoveredName = SBOMGraphsConverter.getProductName(fromTarget: targetName)
            #expect(recoveredName == productName, "Round trip failed for product '\(productName)'")
        }
    }

    @Test("product and module mapping functions are mutually exclusive")
    func productAndModuleMappingExclusivity() {
        // Product target names should not be recognized as modules
        let productTargetNames = ["swiftly-product", "ArgumentParser-product", "AsyncHTTPClient-product"]
        for targetName in productTargetNames {
            #expect(
                SBOMGraphsConverter.getModuleName(fromTarget: targetName) == nil,
                "Product target '\(targetName)' should not be recognized as a module"
            )
            #expect(
                SBOMGraphsConverter.getProductName(fromTarget: targetName) != nil,
                "Product target '\(targetName)' should be recognized as a product"
            )
        }

        // Module target names should not be recognized as products
        let moduleTargetNames = ["Swiftly", "ArgumentParser", "SwiftlyCore"]
        for targetName in moduleTargetNames {
            #expect(
                SBOMGraphsConverter.getProductName(fromTarget: targetName) == nil,
                "Module target '\(targetName)' should not be recognized as a product"
            )
            #expect(
                SBOMGraphsConverter.getModuleName(fromTarget: targetName) != nil,
                "Module target '\(targetName)' should be recognized as a module"
            )
        }
    }

    // MARK: - toProduct and toModule Tests

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