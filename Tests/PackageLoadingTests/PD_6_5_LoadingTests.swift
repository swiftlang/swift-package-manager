//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import _InternalTestSupport
import XCTest

final class PackageDescription6_5LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_5
    }

    func testConditionalPluginUsage() async throws {
        let content = #"""
            import PackageDescription
            let package = Package(
                name: "Foo",
                traits: [
                    .trait(name: "Lint")
                ],
                targets: [
                    .target(
                        name: "Foo",
                        plugins: [
                            .plugin(
                                name: "MyPlugin",
                                condition: .when(
                                    hostPlatforms: [.macOS],
                                    targetPlatforms: [.linux],
                                    traits: ["Lint"]
                                )
                            )
                        ]
                    ),
                    .plugin(
                        name: "MyPlugin",
                        capability: .buildTool()
                    )
                ]
            )
            """#

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        guard case .plugin(name: let name, package: let package, condition: let condition)? = manifest.targets[0].pluginUsages?.first else {
            return XCTFail("expected conditional plugin usage")
        }
        XCTAssertEqual(name, "MyPlugin")
        XCTAssertNil(package)
        XCTAssertEqual(
            condition,
            .init(
                hostPlatformNames: ["macos"],
                targetPlatformNames: ["linux"],
                traits: ["Lint"]
            )
        )
    }

    func testConditionalPluginUsageNilConditionFallback() async throws {
        let content = #"""
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        plugins: [
                            .plugin(name: "MyPlugin")
                        ]
                    ),
                    .plugin(
                        name: "MyPlugin",
                        capability: .buildTool()
                    )
                ]
            )
            """#

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        guard case .plugin(name: let name, package: _, condition: let condition)? = manifest.targets[0].pluginUsages?.first else {
            return XCTFail("expected plugin usage")
        }
        XCTAssertEqual(name, "MyPlugin")
        XCTAssertNil(condition)
    }

    func testConditionalPluginUsageWithPackage() async throws {
        let content = #"""
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [
                    .package(url: "https://github.com/example/Bar.git", from: "1.0.0")
                ],
                targets: [
                    .target(
                        name: "Foo",
                        plugins: [
                            .plugin(
                                name: "BarPlugin",
                                package: "Bar",
                                condition: .when(hostPlatforms: [.macOS])
                            )
                        ]
                    )
                ]
            )
            """#

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        guard case .plugin(name: let name, package: let package, condition: let condition)? = manifest.targets[0].pluginUsages?.first else {
            return XCTFail("expected conditional plugin usage")
        }
        XCTAssertEqual(name, "BarPlugin")
        XCTAssertEqual(package, "Bar")
        XCTAssertEqual(condition, .init(hostPlatformNames: ["macos"]))
    }

    func testConditionalPluginUsageEmptyConditionReturnsNil() async throws {
        let content = #"""
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(
                        name: "Foo",
                        plugins: [
                            .plugin(
                                name: "MyPlugin",
                                condition: .when(hostPlatforms: [], targetPlatforms: [])
                            )
                        ]
                    ),
                    .plugin(
                        name: "MyPlugin",
                        capability: .buildTool()
                    )
                ]
            )
            """#

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        guard case .plugin(name: _, package: _, condition: let condition)? = manifest.targets[0].pluginUsages?.first else {
            return XCTFail("expected plugin usage")
        }
        // Empty platforms should normalize to nil condition
        XCTAssertNil(condition)
    }
}
