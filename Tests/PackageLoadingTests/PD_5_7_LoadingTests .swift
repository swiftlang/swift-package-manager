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
import SPMTestSupport
import TSCBasic
import XCTest

class PackageDescription5_7LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_7
    }

    func testRegistryDependencies() throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "MyPackage",
               dependencies: [
                   .package(id: "x.foo", from: "1.1.1"),
                   .package(id: "x.bar", exact: "1.1.1"),
                   .package(id: "x.baz", .upToNextMajor(from: "1.1.1")),
                   .package(id: "x.qux", .upToNextMinor(from: "1.1.1")),
                   .package(id: "x.quux", "1.1.1" ..< "3.0.0"),
               ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
        XCTAssertEqual(deps["x.foo"], .registry(identity: "x.foo", requirement: .range("1.1.1" ..< "2.0.0")))
        XCTAssertEqual(deps["x.bar"], .registry(identity: "x.bar", requirement: .exact("1.1.1")))
        XCTAssertEqual(deps["x.baz"], .registry(identity: "x.baz", requirement: .range("1.1.1" ..< "2.0.0")))
        XCTAssertEqual(deps["x.qux"], .registry(identity: "x.qux", requirement: .range("1.1.1" ..< "1.2.0")))
        XCTAssertEqual(deps["x.quux"], .registry(identity: "x.quux", requirement: .range("1.1.1" ..< "3.0.0")))
    }

    func testConditionalTargetDependencies() throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [],
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Bar", condition: .when(platforms: [])),
                        .target(name: "Baz", condition: .when(platforms: [.linux])),
                    ]),
                    .target(name: "Bar"),
                    .target(name: "Baz"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        let dependencies = manifest.targets[0].dependencies
        XCTAssertEqual(dependencies[0], .target(name: "Bar", condition: .none))
        XCTAssertEqual(dependencies[1], .target(name: "Baz", condition: .init(platformNames: ["linux"], config: .none)))
    }

    func testConditionalTargetDependenciesDeprecation() throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [],
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Bar", condition: .when(platforms: nil))
                    ]),
                    .target(name: "Bar")
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            if case ManifestParseError.invalidManifestFormat(let error, _) = error {
                XCTAssertMatch(error, .contains("when(platforms:)' was obsoleted"))
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTargetDeprecatedDependencyCase() throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [
                   .package(url: "http://localhost/BarPkg", from: "1.1.1"),
                ],
                targets: [
                    .target(name: "Foo",
                            dependencies: [
                                .productItem(name: "Bar", package: "BarPkg", condition: nil),
                            ]),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadAndValidateManifest(content, observabilityScope: observability.topScope)) { error in
            if case ManifestParseError.invalidManifestFormat(let message, _) = error {
                XCTAssertMatch(message, .contains("error: 'productItem(name:package:condition:)' is unavailable: use .product(name:package:condition) instead."))
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testPlatforms() throws {
        let content =  """
            import PackageDescription
            let package = Package(
               name: "Foo",
               platforms: [
                   .macOS(.v13), .iOS(.v16),
                   .tvOS(.v16), .watchOS(.v9),
                   .macCatalyst(.v16), .driverKit(.v22),
               ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.platforms, [
            PlatformDescription(name: "macos", version: "13.0"),
            PlatformDescription(name: "ios", version: "16.0"),
            PlatformDescription(name: "tvos", version: "16.0"),
            PlatformDescription(name: "watchos", version: "9.0"),
            PlatformDescription(name: "maccatalyst", version: "16.0"),
            PlatformDescription(name: "driverkit", version: "22.0"),
        ])
    }
}
