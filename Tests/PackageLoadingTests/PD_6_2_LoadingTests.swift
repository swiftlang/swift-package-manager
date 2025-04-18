//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import PackageModel
import SourceControl
import XCTest

final class PackageDescription6_2LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_2
    }

    func testDefaultIsolationPerTarget() async throws {
        let content = """
        import PackageDescription
        let package = Package(
            name: "Foo",
            defaultLocalization: "be",
            products: [],
            targets: [
                .target(
                    name: "Foo",
                    swiftSettings: [
                        .defaultIsolation(nil)
                    ]
                ),
                .target(
                    name: "Bar",
                    swiftSettings: [
                        .defaultIsolation(MainActor.self)
                    ]
                )
            ]
        )
        """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, validationDiagnostics) = try await loadAndValidateManifest(
            content,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(validationDiagnostics)
        XCTAssertNoDiagnostics(observability.diagnostics)
    }
}
