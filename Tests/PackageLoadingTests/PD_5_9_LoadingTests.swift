//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
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

final class PackageDescription5_9LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_9
    }

    func testPlatforms() async throws {
        let content =  """
            import PackageDescription
            let package = Package(
               name: "Foo",
               platforms: [
                   .macOS(.v14), .iOS(.v17),
                   .tvOS(.v17), .watchOS(.v10), .visionOS(.v1),
                   .macCatalyst(.v17), .driverKit(.v23),
               ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.platforms, [
                PlatformDescription(name: "macos", version: "14.0"),
                PlatformDescription(name: "ios", version: "17.0"),
                PlatformDescription(name: "tvos", version: "17.0"),
                PlatformDescription(name: "watchos", version: "10.0"),
                PlatformDescription(name: "visionos", version: "1.0"),
                PlatformDescription(name: "maccatalyst", version: "17.0"),
                PlatformDescription(name: "driverkit", version: "23.0"),
            ])
            
            return manifest
        }
    }

    func testMacroTargets() async throws {
        let content = """
            import CompilerPluginSupport
            import PackageDescription

            let package = Package(name: "MyPackage",
                targets: [
                    .macro(name: "MyMacro", swiftSettings: [.define("BEST")], linkerSettings: [.linkedLibrary("best")]),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.targets.count, 1)
            XCTAssertEqual(manifest.targets[0].name, "MyMacro")
            XCTAssertEqual(manifest.targets[0].type, .macro)

            return manifest
        }
    }

    func testPackageAccess() async throws {
        let content = """
            import PackageDescription

            let package = Package(
                name: "MyPackage",
                targets: [
                    .target(name: "PublicTarget", packageAccess: true),
                    .target(name: "PrivateTarget", packageAccess: false),
                    .target(name: "DefaultTarget"),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            // Check target with packageAccess: true
            XCTAssertEqual(manifest.targets[0].name, "PublicTarget")
            XCTAssertTrue(manifest.targets[0].packageAccess)

            // Check target with packageAccess: false
            XCTAssertEqual(manifest.targets[1].name, "PrivateTarget")
            XCTAssertFalse(manifest.targets[1].packageAccess)

            // Check target with default packageAccess (should be true per PackageDescription API)
            XCTAssertEqual(manifest.targets[2].name, "DefaultTarget")
            XCTAssertTrue(manifest.targets[2].packageAccess)

            return manifest
        }
    }

    func testBinaryTargetPackageAccess() async throws {
        // Binary targets always have packageAccess: false. The PackageDescription
        // binaryTarget(…) factory methods do not expose a packageAccess parameter,
        // and they hardcode it to false. This must hold even at tools versions ≥ 5.9
        // where the default packageAccess for regular targets is true.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .binaryTarget(
                        name: "RemoteBinary",
                        url: "https://example.com/RemoteBinary-1.0.0.zip",
                        checksum: "abc123"),
                    .binaryTarget(
                        name: "LocalBinary",
                        path: "LocalBinary.xcframework"),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let targets = Dictionary(uniqueKeysWithValues: manifest.targets.map({ ($0.name, $0) }))

            // Both binary targets must have packageAccess: false regardless of
            // the tools version default (which is true at v5_9+).
            XCTAssertEqual(targets["RemoteBinary"]?.type, .binary)
            XCTAssertEqual(targets["RemoteBinary"]?.packageAccess, false)

            XCTAssertEqual(targets["LocalBinary"]?.type, .binary)
            XCTAssertEqual(targets["LocalBinary"]?.packageAccess, false)

            return manifest
        }
    }

    func testSystemLibraryTargetPackageAccess() async throws {
        // System library targets always have packageAccess: false. The
        // PackageDescription systemLibrary(…) factory method does not expose a
        // packageAccess parameter and hardcodes it to false. This must hold even
        // at tools versions ≥ 5.9 where the default packageAccess for regular
        // targets is true.
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .systemLibrary(
                        name: "CBar",
                        pkgConfig: "bar",
                        providers: [
                            .brew(["bar"]),
                            .apt(["libbar-dev"]),
                        ]),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let target = try XCTUnwrap(manifest.targetMap["CBar"])

            // System library target must have packageAccess: false regardless
            // of the tools version default (which is true at v5_9+).
            XCTAssertEqual(target.type, .system)
            XCTAssertEqual(target.packageAccess, false)
            XCTAssertEqual(target.pkgConfig, "bar")
            XCTAssertEqual(target.providers, [.brew(["bar"]), .apt(["libbar-dev"])])

            return manifest
        }
    }
}
