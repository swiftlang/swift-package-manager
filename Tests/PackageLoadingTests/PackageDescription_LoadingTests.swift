//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import SourceControl
import _InternalTestSupport
import Testing

@Suite(
    .tags(
        .TestSize.medium
    )
)
struct PackageDescriptionLoadingTestsST {

    @Test(
        arguments: [
            ToolsVersion.minimumRequired,
            ToolsVersion.v6_2,
            ToolsVersion.v6_3,
            ToolsVersion.v6_4,
        ]
    )
    func productDeprecatedParameterUnavailableAtV6_2(
        toolVersion: ToolsVersion,
    ) async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [
                    .library(
                        name: "Foo",
                        targets: ["Foo"],
                        deprecated: .unsupported(message: "not yet available")
                    ),
                ],
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        await #expect(throws: (any Error).self) {
            try await PackageDescriptionLoadingTests.loadAndValidateManifest(
                content,
                toolsVersion: toolVersion,
                packageKind: .fileSystem(.root),
                manifestLoader: ManifestLoader(
                    toolchain: try! UserToolchain.default,
                ),
                observabilityScope: observability.topScope,
            )
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
