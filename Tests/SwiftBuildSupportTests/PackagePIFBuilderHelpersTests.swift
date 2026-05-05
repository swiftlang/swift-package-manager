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

import Testing
import SwiftBuildSupport

@Suite(
    .tags(
        .TestSize.small,
        .FunctionalArea.PIF
    )
)
struct PackagePIFBuilderHelpersTests {

    // MARK: - targetName(forProductName:) Tests

    @Test("targetName(forProductName:) converts product names correctly")
    func targetNameForProduct() {
        // Test with various product names
        #expect(PackagePIFBuilder.targetName(forProductName: "swiftly") == "swiftly-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "test-swiftly") == "test-swiftly-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "ArgumentParser") == "ArgumentParser-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "AsyncHTTPClient") == "AsyncHTTPClient-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "OpenAPIRuntime") == "OpenAPIRuntime-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "SystemPackage") == "SystemPackage-product")

        #expect(PackagePIFBuilder.targetName(forProductName: "") == "-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "A") == "A-product")
        #expect(PackagePIFBuilder.targetName(forProductName: "product") == "product-product")
    }

    // MARK: - targetName(forModuleName:) Tests

    @Test("targetName(forModuleName:) converts module names correctly")
    func targetNameForModule() {
        // Test with various module names
        #expect(PackagePIFBuilder.targetName(forModuleName: "Swiftly") == "Swiftly")
        #expect(PackagePIFBuilder.targetName(forModuleName: "TestSwiftly") == "TestSwiftly")
        #expect(PackagePIFBuilder.targetName(forModuleName: "ArgumentParser") == "ArgumentParser")
        #expect(PackagePIFBuilder.targetName(forModuleName: "SwiftlyCore") == "SwiftlyCore")
        #expect(PackagePIFBuilder.targetName(forModuleName: "MacOSPlatform") == "MacOSPlatform")

        // Modules with leading underscores
        #expect(PackagePIFBuilder.targetName(forModuleName: "_CryptoExtras") == "_CryptoExtras")
        #expect(PackagePIFBuilder.targetName(forModuleName: "__AsyncFileSystem") == "__AsyncFileSystem")

        #expect(PackagePIFBuilder.targetName(forModuleName: "") == "")
        #expect(PackagePIFBuilder.targetName(forModuleName: "A") == "A")
    }

    // MARK: - productName(forTargetName:) Tests

    @Test("productName(forTargetName:) converts target names correctly")
    func productNameFromTarget() {
        #expect(PackagePIFBuilder.productName(forTargetName: "swiftly-product") == "swiftly")
        #expect(PackagePIFBuilder.productName(forTargetName: "test-swiftly-product") == "test-swiftly")
        #expect(PackagePIFBuilder.productName(forTargetName: "ArgumentParser-product") == "ArgumentParser")
        #expect(PackagePIFBuilder.productName(forTargetName: "AsyncHTTPClient-product") == "AsyncHTTPClient")
        #expect(PackagePIFBuilder.productName(forTargetName: "OpenAPIRuntime-product") == "OpenAPIRuntime")
        #expect(PackagePIFBuilder.productName(forTargetName: "SystemPackage-product") == "SystemPackage")
        #expect(PackagePIFBuilder.productName(forTargetName: "SwiftBuild-product") == "SwiftBuild")

        #expect(PackagePIFBuilder.productName(forTargetName: "Swiftly") == nil)
        #expect(PackagePIFBuilder.productName(forTargetName: "TestSwiftly") == nil)
        #expect(PackagePIFBuilder.productName(forTargetName: "ArgumentParser") == nil)
        #expect(PackagePIFBuilder.productName(forTargetName: "SwiftlyCore") == nil)
        #expect(PackagePIFBuilder.productName(forTargetName: "MacOSPlatform") == nil)

        #expect(PackagePIFBuilder.productName(forTargetName: "-product") == "")
        #expect(PackagePIFBuilder.productName(forTargetName: "") == nil)
        #expect(PackagePIFBuilder.productName(forTargetName: "product") == nil)
        #expect(PackagePIFBuilder.productName(forTargetName: "my-product-product") == "my-product")
    }

    @Test("productName(forTargetName:) removes TargetSuffix patterns correctly")
    func productNameRemovesSuffixes() {
        // Test -dynamic suffix removal from PACKAGE-PRODUCT GUIDs
        // PACKAGE-PRODUCT:swift-build_SwiftBuild.SwiftBuild-6FA70E1059D35307-dynamic
        #expect(PackagePIFBuilder.productName(forTargetName: "SwiftBuild-dynamic-product") == "SwiftBuild")

        // PACKAGE-PRODUCT:swift-build_SWBProtocol.SWBProtocol-479FEB9464127B49-dynamic
        #expect(PackagePIFBuilder.productName(forTargetName: "SWBProtocol-dynamic-product") == "SWBProtocol")

        // Test -testable suffix removal
        // snippet-extract-4D525650E9464C3A-testable
        #expect(PackagePIFBuilder.productName(forTargetName: "snippet-extract-testable-product") == "snippet-extract")

        // swift-run--4E81F76B4FDE3E48-testable
        #expect(PackagePIFBuilder.productName(forTargetName: "swift-run-testable-product") == "swift-run")

        // swift-experimental-sdk--453A89A57E5CD913-testable
        #expect(PackagePIFBuilder.productName(forTargetName: "swift-experimental-sdk-testable-product") == "swift-experimental-sdk")

        // swift-bootstrap-19E6669016298B47-testable
        #expect(PackagePIFBuilder.productName(forTargetName: "swift-bootstrap-testable-product") == "swift-bootstrap")

        // Test products without suffixes
        #expect(PackagePIFBuilder.productName(forTargetName: "SwiftBuild-product") == "SwiftBuild")
        #expect(PackagePIFBuilder.productName(forTargetName: "ArgumentParser-product") == "ArgumentParser")
    }

    // MARK: - moduleName(forTargetName:) Tests

    @Test("moduleName(forTargetName:) converts target names correctly")
    func moduleNameFromTarget() {
        // Test simple module names (no package prefix)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "Swiftly") == "Swiftly")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "TestSwiftly") == "TestSwiftly")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "ArgumentParser") == "ArgumentParser")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SwiftlyCore") == "SwiftlyCore")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "MacOSPlatform") == "MacOSPlatform")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "LinuxPlatform") == "LinuxPlatform")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SwiftlyWebsiteAPI") == "SwiftlyWebsiteAPI")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SwiftlyDownloadAPI") == "SwiftlyDownloadAPI")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "AsyncHTTPClient") == "AsyncHTTPClient")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "OpenAPIRuntime") == "OpenAPIRuntime")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SPMSQLite3") == "SPMSQLite3")

        // Modules that start with underscores
        #expect(PackagePIFBuilder.moduleName(forTargetName: "_CryptoExtras") == "_CryptoExtras")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "_AsyncFileSystem") == "_AsyncFileSystem")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "_CertificateInternals") == "_CertificateInternals")

        // Test product names (should return nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swiftly-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "test-swiftly-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "ArgumentParser-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "AsyncHTTPClient-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "OpenAPIRuntime-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SystemPackage-product") == nil)

        // Test edge cases
        #expect(PackagePIFBuilder.moduleName(forTargetName: "") == "")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "A") == "A")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "my-product-product") == nil)

        // Test resource bundle package_module target format (with underscores)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-nio_NIOPosix") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-nio-ssl_NIOSSL") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-crypto_Crypto") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-crypto__CryptoExtras") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-nio__NIOBase64") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-nio__NIODataStructures") == nil)

        // Test modules with multiple leading underscores
        #expect(PackagePIFBuilder.moduleName(forTargetName: "___ModuleName") == "___ModuleName")
    }

    @Test("moduleName(forTargetName:) removes TargetSuffix patterns correctly")
    func moduleNameRemovesSuffixes() {
        // Test -dynamic suffix removal from PACKAGE-TARGET GUIDs
        // PACKAGE-TARGET:SWBTaskConstruction--13A05A6A6704C663-dynamic
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SWBTaskConstruction-dynamic") == "SWBTaskConstruction")

        // PACKAGE-TARGET:_IntegrationTestSupport-1FB010E086040497-dynamic
        #expect(PackagePIFBuilder.moduleName(forTargetName: "_IntegrationTestSupport-dynamic") == "_IntegrationTestSupport")

        // PACKAGE-TARGET:_AsyncFileSystem--4E4E671E738B868E-dynamic
        #expect(PackagePIFBuilder.moduleName(forTargetName: "_AsyncFileSystem-dynamic") == "_AsyncFileSystem")

        // PACKAGE-TARGET:PackageSigning--7F242844F5C56277-dynamic
        #expect(PackagePIFBuilder.moduleName(forTargetName: "PackageSigning-dynamic") == "PackageSigning")

        // Test -testable suffix removal
        // snippet-extract-4D525650E9464C3A-testable
        #expect(PackagePIFBuilder.moduleName(forTargetName: "snippet-extract-testable") == "snippet-extract")

        // swift-run--4E81F76B4FDE3E48-testable
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-run-testable") == "swift-run")

        // swift-experimental-sdk--453A89A57E5CD913-testable
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-experimental-sdk-testable") == "swift-experimental-sdk")

        // swift-bootstrap-19E6669016298B47-testable
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-bootstrap-testable") == "swift-bootstrap")

        // Test modules without suffixes
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SwiftBuild") == "SwiftBuild")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "_AsyncFileSystem") == "_AsyncFileSystem")
        #expect(PackagePIFBuilder.moduleName(forTargetName: "ArgumentParser") == "ArgumentParser")

        // Test that product targets still return nil even with suffixes
        #expect(PackagePIFBuilder.moduleName(forTargetName: "SwiftBuild-dynamic-product") == nil)
        #expect(PackagePIFBuilder.moduleName(forTargetName: "swift-run-testable-product") == nil)
    }

    // MARK: - Round-trip and Mutual Exclusivity Tests

    @Test("name mapping functions are inverses for products")
    func productNameMappingRoundTrip() {
        let productNames = ["swiftly", "test-swiftly", "ArgumentParser", "AsyncHTTPClient", "OpenAPIRuntime"]

        for productName in productNames {
            let targetName = PackagePIFBuilder.targetName(forProductName: productName)
            let recoveredName = PackagePIFBuilder.productName(forTargetName: targetName)
            #expect(recoveredName == productName, "Round trip failed for product '\(productName)'")
        }
    }

    @Test("product and module mapping functions are mutually exclusive")
    func productAndModuleMappingExclusivity() {
        // Product target names should not be recognized as modules
        let productTargetNames = ["swiftly-product", "ArgumentParser-product", "AsyncHTTPClient-product"]
        for targetName in productTargetNames {
            #expect(
                PackagePIFBuilder.moduleName(forTargetName: targetName) == nil,
                "Product target '\(targetName)' should not be recognized as a module"
            )
            #expect(
                PackagePIFBuilder.productName(forTargetName: targetName) != nil,
                "Product target '\(targetName)' should be recognized as a product"
            )
        }

        // Module target names should not be recognized as products
        let moduleTargetNames = ["Swiftly", "ArgumentParser", "SwiftlyCore"]
        for targetName in moduleTargetNames {
            #expect(
                PackagePIFBuilder.productName(forTargetName: targetName) == nil,
                "Module target '\(targetName)' should not be recognized as a product"
            )
            #expect(
                PackagePIFBuilder.moduleName(forTargetName: targetName) != nil,
                "Module target '\(targetName)' should be recognized as a module"
            )
        }
    }
}
