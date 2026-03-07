//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SourceControl
import _InternalTestSupport
import XCTest

final class ParsingLoaderTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_2
    }

    override var environment: [String : String]? {
        ["SWIFT_TARGET_NAME": "MyTarget"]
    }

    func testPoundIf() async throws {
        let content =  """
            import PackageDescription
            #if os(macOS)
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: "MacTarget")
                ],
            )
            #else
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: "OtherTarget")
                ],
            )
            #endif
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
            #if os(macOS)
            XCTAssertEqual(manifest.targets[0].name, "MacTarget")
            #else
            XCTAssertEqual(manifest.targets[0].name, "OtherTarget")
            #endif
            return manifest
        }
    }

    func testPoundIfErrors() async throws {
        let content =  """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: "MyTarget")
                ],
            )

            #if compiler(>=5.3) && BAD_CODE
            this is bad
            #endif
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
            XCTAssertEqual(manifest.targets[0].name, "MyTarget")
            return manifest
        }
    }

    func testEnvironment() async throws {
        let content =  """
            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                  .target(name: Context.environment["SWIFT_TARGET_NAME"] ?? "OtherTarget")
                ],
            )
            """

        // NOTE: non-parsing manifest loader doesn't support testing the
        // environment.
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            customManifestLoader: self.parsingManifestLoader,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertNoDiagnostics(validationDiagnostics)

        XCTAssertEqual(manifest.targets.count, 1)
        XCTAssertEqual(manifest.targets[0].name, "MyTarget")
    }
}
