//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
import _InternalTestSupport

import struct SPMBuildCore.BuildSystemProvider

extension PackageCommandTests.PackageResolveCommandTests {

    @Suite(
        .tags(
            .Feature.Deprecation,
        ),
    )
    struct ProductDeprecation {

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func resolveEmitsWarningForConsumerOfDeprecatedProduct(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        buildSystem: buildSystem,
                    )
                ) { error in
                    #expect(
                        error.stderr.contains(
                            "error: 'consumer': product 'PaperExperimental' from package 'producer' is unsupported: PaperExperimental is going away with no replacement.",
                        ),
                        "stdout:\n\(error.stdout)",
                    )
                     #expect(
                        error.stderr.contains(
                            "warning: 'consumer': product 'PaperLegacy' from package 'producer' is unsupported: PaperLegacy is superseded by Paper. Use 'Paper' instead."
                        ),
                        "stdout:\n\(error.stdout)",
                    )
               }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func resolveEscalatesToErrorViaXswiftcWarningsAsErrors(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "resolve",
                            "-Xswiftc", "-warnings-as-errors",
                        ],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    #expect(
                        error.stderr.contains(
                            "error: 'consumer': product 'PaperLegacy' from package 'producer' is unsupported: PaperLegacy is superseded by Paper. Use 'Paper' instead."
                        ),
                        "stdout:\n\(error.stdout)",
                    )
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func resolveDoesNotWarnForNonConsumingPackage(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/producer") { fixturePath in
                let (_, stderr) = try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["resolve"],
                    buildSystem: buildSystem,
                )
                #expect(!stderr.contains("is unsupported"))
            }
        }
    }


}
