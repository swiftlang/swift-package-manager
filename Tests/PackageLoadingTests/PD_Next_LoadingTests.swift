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

class PackageDescriptionNextLoadingTests: PackageDescriptionLoadingTests {
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

    func testSwiftWarningTreatingRules() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [],
                targets: [
                    .target(
                        name: "Foo",
                        swiftSettings: [
                            .treatAllWarnings(as: .error),
                            .treatWarning(name: "DeprecatedDeclaration", as: .warning),
            
                        ]
                    ),
                    .target(
                        name: "Bar",
                        swiftSettings: [
                            .treatAllWarnings(as: .warning),
                            .treatWarning(name: "DeprecatedDeclaration", as: .error),
                        ]
                    )
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(validationDiagnostics)
        testDiagnostics(observability.diagnostics) { result in
            result.checkIsEmpty()
        }
    }
}
