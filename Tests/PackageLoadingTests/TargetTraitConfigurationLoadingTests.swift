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
import PackageModel
import _InternalTestSupport
import XCTest

final class TargetTraitConfigurationLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_5
    }

    func testTestTargetTraitConfigurations() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                traits: ["Trait1", "Trait2"],
                targets: [
                    .target(name: "Foo"),
                    .testTarget(
                        name: "FooTests",
                        dependencies: ["Foo"],
                        traitConfigurations: [
                            .default,
                            .enableAllTraits,
                            .disableAllTraits,
                            .enabledTraits(["Trait1", "Trait2"]),
                        ]
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets[0].traitConfigurations, nil)
        XCTAssertEqual(manifest.targets[1].traitConfigurations, [
            .default,
            .enableAllTraits,
            .disableAllTraits,
            .enabledTraits(["Trait1", "Trait2"]),
        ])
    }

    func testTestTargetWithoutTraitConfigurations() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .testTarget(name: "FooTests"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets[0].traitConfigurations, nil)
    }

    func testEmptyEnabledTraitsNormalizesToDisableAllTraits() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .testTarget(
                        name: "FooTests",
                        traitConfigurations: [.enabledTraits([])]
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets[0].traitConfigurations, [.disableAllTraits])
    }

    func testTraitConfigurationsDisallowedOnRegularTarget() async throws {
        let content = """
            import PackageDescription
            var target = Target.target(name: "Foo")
            target.traitConfigurations = [.default]
            let package = Package(name: "Foo", targets: [target])
            """

        let observability = ObservabilitySystem.makeForTesting()
        await XCTAssertAsyncThrowsError(try await loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            XCTAssertEqual(
                error.localizedDescription,
                "target 'Foo' is assigned a property 'traitConfigurations' which is not accepted " +
                "for the regular target type. The current property value has " +
                "the following representation: [PackageModel.TraitConfiguration.default]."
            )
        }
    }

    func testEmptyTraitConfigurationsList() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .testTarget(
                        name: "FooTests",
                        traitConfigurations: []
                    ),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        await XCTAssertAsyncThrowsError(try await loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            XCTAssertEqual(
                error.localizedDescription,
                "test target 'FooTests' must declare at least one trait configuration when 'traitConfigurations' is specified"
            )
        }
    }
}
