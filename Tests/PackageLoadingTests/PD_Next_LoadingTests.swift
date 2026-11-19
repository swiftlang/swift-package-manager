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

    func testUnionOfVersionsDependencies() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "MyPackage",
               dependencies: [
                    // labeled `versions:` variadic, mixing ranges and bare (exact) versions
                   .package(url: "http://localhost/foo", versions: "1.1.0"..<"2.0.0", "2.1.0"..<"3.0.0", "3.3.0", "5.1.3"),
                   .package(url: "http://localhost/bar", versions: "1.0.0"..<"1.5.0", "2.0.0"..<"2.5.0"),
                    // registry
                   .package(id: "x.foo", versions: "1.1.0"..<"2.0.0", "3.3.0"),
                   .package(id: "x.bar", versions: "1.0.0"..<"1.5.0", "2.0.0"..<"2.5.0"),
               ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertFalse(observability.diagnostics.hasErrors)
        XCTAssertNoDiagnostics(validationDiagnostics)

        // A bare version literal becomes the single-version range `v ..< v.nextPatch`.
        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map { ($0.identity.description, $0) })
        XCTAssertEqual(deps["foo"], .remoteSourceControl(identity: .plain("foo"), url: "http://localhost/foo", requirement: .ranges(["1.1.0"..<"2.0.0", "2.1.0"..<"3.0.0", "3.3.0"..<"3.3.1", "5.1.3"..<"5.1.4"])))
        XCTAssertEqual(deps["bar"], .remoteSourceControl(identity: .plain("bar"), url: "http://localhost/bar", requirement: .ranges(["1.0.0"..<"1.5.0", "2.0.0"..<"2.5.0"])))
        XCTAssertEqual(deps["x.foo"], .registry(identity: "x.foo", requirement: .ranges(["1.1.0"..<"2.0.0", "3.3.0"..<"3.3.1"])))
        XCTAssertEqual(deps["x.bar"], .registry(identity: "x.bar", requirement: .ranges(["1.0.0"..<"1.5.0", "2.0.0"..<"2.5.0"])))
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

    func testAnyAppleOSPlatform() async throws {
        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo",
                   platforms: [
                       .anyAppleOS(.v26), .driverKit(.v27),
                   ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.platforms, [
                PlatformDescription(name: "driverkit", version: "27.0"),
                PlatformDescription(name: "macos", version: "26.0"),
                PlatformDescription(name: "maccatalyst", version: "26.0"),
                PlatformDescription(name: "ios", version: "26.0"),
                PlatformDescription(name: "tvos", version: "26.0"),
                PlatformDescription(name: "watchos", version: "26.0"),
                PlatformDescription(name: "visionos", version: "26.0"),
            ])
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo",
                   platforms: [
                       .macOS(.v27), .anyAppleOS(.v26), .iOS(.v27),
                   ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.platforms, [
                PlatformDescription(name: "macos", version: "27.0"),
                PlatformDescription(name: "ios", version: "27.0"),
                PlatformDescription(name: "maccatalyst", version: "26.0"),
                PlatformDescription(name: "tvos", version: "26.0"),
                PlatformDescription(name: "watchos", version: "26.0"),
                PlatformDescription(name: "visionos", version: "26.0"),
            ])
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo",
                   platforms: [
                       .anyAppleOS("18.0"),
                   ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            await XCTAssertAsyncThrowsError(try await loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") { error in
                if case ManifestParseError.runtimeManifestErrors(let errors) = error {
                    XCTAssertEqual(errors, ["invalid anyAppleOS version 18.0; the minimum major version should be 26"])
                } else {
                    XCTFail("unexpected error: \(error)")
                }
            }
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo",
                   platforms: [
                       .anyAppleOS(.v26), .anyAppleOS(.v27),
                   ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            await XCTAssertAsyncThrowsError(try await loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") { error in
                if case ManifestParseError.runtimeManifestErrors(let errors) = error {
                    XCTAssertEqual(errors, ["found multiple declarations for the platform: anyAppleOS"])
                } else {
                    XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testAnyAppleOSCondition() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .target(name: "Foo", swiftSettings: [.define("APPLE", .when(platforms: [.anyAppleOS]))]),
               ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets[0].settings[0].condition, PackageConditionDescription(platformNames: ["anyappleos"]))
    }
}
