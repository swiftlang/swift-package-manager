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
import PackageLoading
import PackageModel
import _InternalTestSupport
import XCTest

class PackageDescription6_2LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v6_0  // TODO: Update to .v6_2 when it's available
    }

    func testWarningControlFlags() async throws {
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

        // Skip on Windows if not running in smoke test pipeline
        // See: https://github.com/swiftlang/swift-package-manager/issues/8543
        if isWindows && !CiEnvironment.runningInSmokeTestPipeline {
            throw XCTSkip("Skipping test on Windows due to compilation errors")
        }

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)
            
            // Verify the settings were parsed correctly
            let fooTarget = manifest.targets.first { $0.name == "Foo" }
            let barTarget = manifest.targets.first { $0.name == "Bar" }
            
            XCTAssertNotNil(fooTarget)
            XCTAssertNotNil(barTarget)
            
            return manifest
        }
    }
}
private var isWindows: Bool {
#if os(Windows)
    true
#else
    false
#endif
}

