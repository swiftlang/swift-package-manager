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
import Basics
import PackageLoading
import PackageModel
import _InternalTestSupport
import Testing

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

    func testTemplate() async throws {
        let content = """
        // swift-tools-version:999.0.0
        import PackageDescription

        let package = Package(
            name: "SimpleTemplateExample",
            products: .template(name: "ExecutableTemplate"),
            dependencies: [
                .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
                .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2"),
            ],
            targets: .template(
                name: "ExecutableTemplate",
                dependencies: [
                    .product(name: "ArgumentParser", package: "swift-argument-parser"),
                    .product(name: "SystemPackage", package: "swift-system"),
                ],

                initialPackageType: .executable,
                description: "This is a simple template that uses Swift string interpolation."
            )
        )    
        """
        let observability = ObservabilitySystem.makeForTesting()

        let (_, validationDiagnostics) = try await PackageDescriptionLoadingTests
            .loadAndValidateManifest(
                content,
                toolsVersion: .vNext,
                packageKind: .fileSystem(.root),
                manifestLoader: ManifestLoader(
                    toolchain: try! UserToolchain.default
                ),
                observabilityScope: observability.topScope
            )
        try expectDiagnostics(validationDiagnostics) { results in
            results.checkIsEmpty()
        }
        try expectDiagnostics(observability.diagnostics) { results in
            results.checkIsEmpty()
        }
    }
}

