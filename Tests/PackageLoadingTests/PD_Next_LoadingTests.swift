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

    // MARK: - Product deprecation (SE-NNNN)

    func testProductDeprecationOnLibraryWithRenamedReplacement() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .library(
                        name: "Old",
                        targets: ["Old"],
                        deprecated: .unsupported(
                            message: "Use New instead.",
                            replacement: .renamed(to: "New")
                        )
                    ),
                ],
                targets: [
                    .target(name: "Old"),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        XCTAssertEqual(product.name, "Old")
        let deprecation = try XCTUnwrap(product.deprecation)
        XCTAssertEqual(deprecation.message, "Use New instead.")
        XCTAssertEqual(deprecation.replacement, .renamed(to: "New"))
    }

    func testProductDeprecationOnLibraryWithInPackageReplacement() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .library(
                        name: "Old",
                        targets: ["Old"],
                        deprecated: .unsupported(
                            message: "Migrate to OtherPkg.",
                            replacement: .inPackage("other-pkg", product: "OtherProduct")
                        )
                    ),
                ],
                targets: [
                    .target(name: "Old"),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        let deprecation = try XCTUnwrap(product.deprecation)
        XCTAssertEqual(
            deprecation.replacement,
            .inPackage(package: "other-pkg", product: "OtherProduct")
        )
    }

    func testProductDeprecationOnLibraryWithoutReplacement() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .library(
                        name: "Old",
                        targets: ["Old"],
                        deprecated: .unsupported(
                            message: "Retired with no replacement."
                        )
                    ),
                ],
                targets: [
                    .target(name: "Old"),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        let deprecation = try XCTUnwrap(product.deprecation)
        XCTAssertEqual(deprecation.message, "Retired with no replacement.")
        XCTAssertNil(deprecation.replacement)
    }

    func testProductDeprecationOnLibraryWithEmptyUnsupported() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .library(
                        name: "Old",
                        targets: ["Old"],
                        deprecated: .unsupported()
                    ),
                ],
                targets: [
                    .target(name: "Old"),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        let deprecation = try XCTUnwrap(product.deprecation)
        XCTAssertNil(deprecation.message)
        XCTAssertNil(deprecation.replacement)
    }

    func testProductDeprecationOnExecutable() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .executable(
                        name: "old-tool",
                        targets: ["old-tool"],
                        deprecated: .unsupported(
                            message: "Use new-tool instead.",
                            replacement: .inPackage("tools", product: "new-tool")
                        )
                    ),
                ],
                targets: [
                    .executableTarget(name: "old-tool"),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        XCTAssertEqual(product.type, .executable)
        let deprecation = try XCTUnwrap(product.deprecation)
        XCTAssertEqual(deprecation.message, "Use new-tool instead.")
        XCTAssertEqual(
            deprecation.replacement,
            .inPackage(package: "tools", product: "new-tool")
        )
    }

    func testProductDeprecationOnPlugin() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .plugin(
                        name: "OldPlugin",
                        targets: ["OldPlugin"],
                        deprecated: .unsupported(
                            message: "Use NewPlugin instead.",
                            replacement: .renamed(to: "NewPlugin")
                        )
                    ),
                ],
                targets: [
                    .plugin(
                        name: "OldPlugin",
                        capability: .command(intent: .custom(verb: "old", description: "old plugin"))
                    ),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        XCTAssertEqual(product.type, .plugin)
        let deprecation = try XCTUnwrap(product.deprecation)
        XCTAssertEqual(deprecation.replacement, .renamed(to: "NewPlugin"))
    }

    func testProductWithoutDeprecatedParameterHasNilDeprecation() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Test",
                products: [
                    .library(name: "Foo", targets: ["Foo"]),
                ],
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let product = try XCTUnwrap(manifest.products.first)
        XCTAssertNil(product.deprecation)
    }
}
