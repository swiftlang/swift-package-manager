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

    func testLiterateTargets() async throws {
        let content = """
            import CompilerPluginSupport
            import PackageDescription

            let package = Package(name: "MyPackage",
                targets: [
                    .target(name: "Foo", literate: true),
                    .executableTarget(name: "Bar", literate: true),
                    .testTarget(name: "Baz", literate: true),
                    .macro(name: "Qux", literate: true),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, diagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertEqual(diagnostics.count, 0, "unexpected diagnostics: \(diagnostics)")

        XCTAssertEqual(manifest.targets.map(\.name), ["Foo", "Bar", "Baz", "Qux"])
        for target in manifest.targets {
            XCTAssertTrue(target.literate, "expected \(target.name) to be literate")
        }
    }

    func testLiterateTargetsDefaultToFalse() async throws {
        let content = """
            import PackageDescription

            let package = Package(name: "MyPackage",
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, diagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertEqual(diagnostics.count, 0, "unexpected diagnostics: \(diagnostics)")

        XCTAssertEqual(manifest.targets.map(\.literate), [false])
    }
}
