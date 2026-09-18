//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
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

final class PackageDescriptionNextLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .vNext
    }

    func testImplicitFoundationImportFails() async throws {
        let content = """
            import PackageDescription

            _ = FileManager.default

            let package = Package(name: "MyPackage")
            """

        let observability = ObservabilitySystem.makeForTesting()
        await XCTAssertAsyncThrowsError(try await loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") {
            if case ManifestParseError.invalidManifestFormat(let error, _, _) = $0 {
                XCTAssertMatch(error, .contains("cannot find 'FileManager' in scope"))
            } else {
                XCTFail("unexpected error: \($0)")
            }
        }
    }

    func testBuildConfigurationConditionalTargetDependencies() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [
                    .package(path: "/Baz"),
                ],
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Biz"),
                        .target(name: "Bar", condition: .when(configuration: .debug)),
                        .product(name: "Baz", package: "Baz", condition: .when(configuration: .release)),
                        .byName(name: "Bar", condition: .when(platforms: [.macOS], configuration: .debug)),
                    ]),
                    .target(name: "Bar"),
                    .target(name: "Biz"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        let dependencies = manifest.targets[0].dependencies
        XCTAssertEqual(dependencies[0], .target(name: "Biz"))
        XCTAssertEqual(dependencies[1], .target(name: "Bar", condition: PackageConditionDescription(config: "debug")))
        XCTAssertEqual(dependencies[2], .product(name: "Baz", package: "Baz", condition: PackageConditionDescription(config: "release")))
        XCTAssertEqual(
            dependencies[3],
            .byName(name: "Bar", condition: PackageConditionDescription(platformNames: ["macos"], config: "debug"))
        )
    }

    func testTargetDependencyConditionWithoutAnyCriteria() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Bar", condition: .when(platforms: [], configuration: nil, traits: nil)),
                        .target(name: "Biz", condition: .when(platforms: [], configuration: .debug, traits: nil)),
                    ]),
                    .target(name: "Bar"),
                    .target(name: "Biz"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        let dependencies = manifest.targets[0].dependencies
        // A condition with no criteria at all is the same as declaring no condition.
        XCTAssertEqual(dependencies[0], .target(name: "Bar"))
        // An empty platform list does not discard the other criteria.
        XCTAssertEqual(dependencies[1], .target(name: "Biz", condition: PackageConditionDescription(config: "debug")))
    }
}
