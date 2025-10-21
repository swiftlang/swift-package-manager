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
import Testing

struct PackageDescription6_2LoadingTests {
    @Test
    func warningControlFlags() async throws {
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
        try await withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8543: there are compilation errors on Windows") {
            let (_, validationDiagnostics) = try await PackageDescriptionLoadingTests
                .loadAndValidateManifest(
                    content,
                    toolsVersion: .v6_2,
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
        } when: {
            isWindows && !CiEnvironment.runningInSmokeTestPipeline
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
