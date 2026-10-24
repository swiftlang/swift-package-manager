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
}
