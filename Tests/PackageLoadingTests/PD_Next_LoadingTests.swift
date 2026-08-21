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

    func testExactVersionIdentifierDependencies() async throws {
        let content = """
            import PackageDescription

            let package = Package(
                name: "MyPackage",
                dependencies: [
                    .package(url: "http://localhost/foo", exact: "1.1.1+debug"),
                    .package(id: "org.foo", exact: "1.1.1+release"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        let dependencies = Dictionary(
            uniqueKeysWithValues: manifest.dependencies.map { ($0.identity.description, $0) }
        )
        XCTAssertEqual(
            dependencies["foo"],
            .remoteSourceControl(
                identity: .plain("foo"),
                url: "http://localhost/foo",
                requirement: .exact("1.1.1+debug")
            )
        )
        XCTAssertEqual(
            dependencies["org.foo"],
            .registry(identity: "org.foo", requirement: .exact("1.1.1+release"))
        )
    }
}
