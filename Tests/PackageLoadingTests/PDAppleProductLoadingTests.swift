/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basics
import TSCUtility
import _InternalTestSupport
import PackageModel
import PackageLoading

class PackageDescriptionAppleProductLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .vNext
    }

    func testApplicationProducts() throws {
      #if ENABLE_APPLE_PRODUCT_TYPES
        let content = """
            import PackageDescription
            import AppleProductTypes
            let package = Package(
                name: "Foo",
                products: [
                    .iOSApplication(
                        name: "Foo",
                        targets: ["Foo"],
                        bundleIdentifier: "com.my.app",
                        teamIdentifier: "ZXYTEAM123",
                        displayVersion: "1.4.2 Extra Cool",
                        bundleVersion: "1.4.2",
                        appIcon: .asset("icon"),
                        accentColor: .asset("accentColor"),
                        supportedDeviceFamilies: [.pad, .mac],
                        supportedInterfaceOrientations: [.portrait, .portraitUpsideDown(), .landscapeRight(.when(deviceFamilies: [.mac]))],
                        capabilities: [
                            .camera(purposeString: "All the better to see you with…"),
                            .microphone(purposeString: "All the better to hear you with…", .when(deviceFamilies: [.pad, .phone])),
                            .localNetwork(purposeString: "Communication is key…", bonjourServiceTypes: ["_ipp._tcp"], .when(deviceFamilies: [.mac]))
                        ],
                        appCategory: .developerTools
                    ),
                ],
                targets: [
                    .executableTarget(
                        name: "Foo"
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        // Check the targets.  We expect to have a single executable target.
        XCTAssertEqual(manifest.targets.count, 1)
        let mainTarget = manifest.targets[0]
        XCTAssertEqual(mainTarget.type, .executable)
        XCTAssertEqual(mainTarget.name, "Foo")

        // Check the products.  We expect to have a single executable product with iOS-specific settings.
        XCTAssertEqual(manifest.products.count, 1)
        let appProduct = manifest.products[0]

        // Check the core properties and basic settings of the application product.
        XCTAssertEqual(appProduct.type, .executable)
        XCTAssertEqual(appProduct.settings.count, 5)
        XCTAssertTrue(appProduct.settings.contains(.bundleIdentifier("com.my.app")))
        XCTAssertTrue(appProduct.settings.contains(.bundleVersion("1.4.2")))

        // Find the "iOS Application Info" setting.
        var appInfoSetting: ProductSetting.IOSAppInfo? = nil
        for case let ProductSetting.iOSAppInfo(value) in appProduct.settings  {
            appInfoSetting = .init(value)
        }
        guard let appInfoSetting = appInfoSetting else {
            return XCTFail("product has no .iOSAppInfo() setting")
        }

        // Check the specific properties of the iOS Application Info.
        XCTAssertEqual(appInfoSetting.appIcon, .asset(name: "icon"))
        XCTAssertEqual(appInfoSetting.accentColor, .asset(name: "accentColor"))
        XCTAssertEqual(appInfoSetting.supportedDeviceFamilies, [.pad, .mac])
        XCTAssertEqual(appInfoSetting.supportedInterfaceOrientations, [
            .portrait(condition: nil),
            .portraitUpsideDown(condition: nil),
            .landscapeRight(condition: .init(deviceFamilies: [.mac]))
        ])
        XCTAssertEqual(appInfoSetting.capabilities, [
            .init(purpose: "camera", purposeString: "All the better to see you with…", condition: nil),
            .init(purpose: "microphone", purposeString: "All the better to hear you with…", condition: .init(deviceFamilies: [.pad, .phone])),
            .init(purpose: "localNetwork", purposeString: "Communication is key…", bonjourServiceTypes: ["_ipp._tcp"], condition: .init(deviceFamilies: [.mac]))
        ])
        XCTAssertEqual(appInfoSetting.appCategory?.rawValue, "public.app-category.developer-tools")
      #else
        throw XCTSkip("ENABLE_APPLE_PRODUCT_TYPES is not set")
      #endif
    }
}
