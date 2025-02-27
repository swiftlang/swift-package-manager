//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
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

final class PackageDescription6_2LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_2
    }

    func testWarningControlFlags() async throws {
        try XCTSkipOnWindows(because: "https://github.com/swiftlang/swift-package-manager/issues/8543: there are compilation errors")

        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [],
                targets: [
                    .target(
                        name: "Foo",
                        cSettings: [
                            .enableWarning("implicit-fallthrough"),
                            .disableWarning("unused-parameter"),
                            .treatAllWarnings(as: .error),
                            .treatWarning("deprecated-declarations", as: .warning),
                        ],
                        cxxSettings: [
                            .enableWarning("implicit-fallthrough"),
                            .disableWarning("unused-parameter"),
                            .treatAllWarnings(as: .warning),
                            .treatWarning("deprecated-declarations", as: .error),
                        ],
                        swiftSettings: [
                            .treatAllWarnings(as: .error),
                            .treatWarning("DeprecatedDeclaration", as: .warning),
                        ]
                    ),
                    .target(
                        name: "Bar",
                        cSettings: [
                            .enableWarning("implicit-fallthrough"),
                            .disableWarning("unused-parameter"),
                            .treatAllWarnings(as: .warning),
                            .treatWarning("deprecated-declarations", as: .error),
                        ],
                        cxxSettings: [
                            .enableWarning("implicit-fallthrough"),
                            .disableWarning("unused-parameter"),
                            .treatAllWarnings(as: .error),
                            .treatWarning("deprecated-declarations", as: .warning),
                        ],
                        swiftSettings: [
                            .treatAllWarnings(as: .warning),
                            .treatWarning("DeprecatedDeclaration", as: .error),
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
