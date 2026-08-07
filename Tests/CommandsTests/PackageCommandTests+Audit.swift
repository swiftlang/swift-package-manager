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

import Foundation
import Testing
import _InternalTestSupport

import struct SPMBuildCore.BuildSystemProvider

extension PackageCommandTests.PackageAuditCommandTests {

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
        func auditReportsDeprecatedProductsInJson(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                try await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--format", "json",
                        ],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    // Even without --allow-deprecations, the JSON payload is
                    // written to stdout before the process exits non-zero.
                    let data = Data(error.stdout.utf8)
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let deprecated = root["deprecated"] as? [String: Any],
                          let products = deprecated["products"] as? [[String: Any]] else {
                        Issue.record("audit output is not valid JSON. stdout:\n\(error.stdout)")
                        return
                    }
                    let byProduct = Dictionary(uniqueKeysWithValues: products.compactMap {
                        (product) -> (String, [String: Any])? in
                        guard let name = product["product"] as? String else { return nil }
                        return (name, product)
                    })

                    // Only the two products consumed by the local package should
                    // appear when --include-transitive is not passed.
                    #expect(byProduct.count == 2, "unexpected products: \(byProduct.keys.sorted())")

                    let paperLegacy = try #require(byProduct["PaperLegacy"])
                    #expect(paperLegacy["package"] as? String == "producer")
                    #expect(paperLegacy["type"] as? String == "library")
                    #expect(paperLegacy["message"] as? String == "PaperLegacy is superseded by Paper.")
                    let paperLegacyReplacement = try #require(paperLegacy["replacement"] as? [String: Any])
                    #expect(paperLegacyReplacement["kind"] as? String == "renamed")
                    #expect(paperLegacyReplacement["to"] as? String == "Paper")
                    #expect(paperLegacy["usedBy"] as? [String] == ["MyApp"])

                    let experimental = try #require(byProduct["PaperExperimental"])
                    #expect(experimental["type"] as? String == "library")
                    #expect(experimental["message"] as? String == "PaperExperimental is going away with no replacement.")
                    #expect(experimental["replacement"] == nil)
                    #expect(experimental["usedBy"] as? [String] == ["MyLib"])
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditReportsDeprecatedProductsInText(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--format", "text",
                        ],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    #expect(
                        error.stdout.contains("PaperLegacy"),
                        "stderr:\n\(error.stderr)",
                    )
                    #expect(
                        error.stdout.contains("PaperLegacy is superseded by Paper."),
                        "stderr:\n\(error.stderr)",
                    )
                    #expect(
                        error.stdout.contains("Use 'Paper' instead."),
                        "stderr:\n\(error.stderr)",
                    )
                    #expect(
                        error.stdout.contains("PaperExperimental"),
                        "stderr:\n\(error.stderr)",
                    )
                    #expect(
                        error.stdout.contains("PaperExperimental is going away with no replacement."),
                        "stderr:\n\(error.stderr)",
                    )
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditExitsNonZeroWhenDeprecatedProductsFound(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                try await #expect(throws: (any Error).self) {
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: ["audit"],
                        buildSystem: buildSystem,
                    )
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditExitsZeroWithAllowDeprecationsFlag(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                try await #expect(throws: Never.self) {
                    let (_, _) = try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--allow-deprecations",
                        ],
                        buildSystem: buildSystem,
                    )
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditRejectsInvalidFormat(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                try await #expect(throws: (any Error).self ) {
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--format", "invalid",
                        ],
                        buildSystem: buildSystem,
                    )
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditOnCleanPackageEmitsEmptyReport(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            // The third-party package vends `OldThirdParty` (deprecated) but no
            // third-party target consumes it, and third-party has no package
            // dependencies. With --include-transitive not passed, the report
            // must be empty.
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                let (stdout, _) = try await executeSwiftPackage(
                    fixturePath.appending("third-party"),
                    configuration: .debug,
                    extraArgs: [
                        "audit",
                        "--format", "json",
                    ],
                    buildSystem: buildSystem,
                )
                let data = Data(stdout.utf8)
                let root = try #require(
                    try JSONSerialization.jsonObject(with: data) as? [String: Any],
                )
                let deprecated = try #require(root["deprecated"] as? [String: Any])
                let products = try #require(deprecated["products"] as? [[String: Any]])
                #expect(products.isEmpty, "unexpected products: \(products)")
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditFromProducerReportsThirdPartyProductConsumedByProducerTarget(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            // When the producer package is the root of the audit, its own targets
            // become the "consumer targets" for reporting purposes. The `Paper`
            // target consumes `OldThirdParty` from the third-party package, so
            // OldThirdParty must appear with `usedBy: ["Paper"]`. The producer's
            // own deprecated products (PaperLegacy, PaperExperimental,
            // paper-tool-old) are NOT consumed by any producer target and must
            // therefore be omitted when --include-transitive is not passed.
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                try await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("producer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--format", "json",
                        ],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    let data = Data(error.stdout.utf8)
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let deprecated = root["deprecated"] as? [String: Any],
                          let products = deprecated["products"] as? [[String: Any]] else {
                        Issue.record("audit output is not valid JSON. stdout:\n\(error.stdout)")
                        return
                    }
                    let byProduct = Dictionary(uniqueKeysWithValues: products.compactMap {
                        (product) -> (String, [String: Any])? in
                        guard let name = product["product"] as? String else { return nil }
                        return (name, product)
                    })
                    #expect(byProduct.count == 1, "unexpected products: \(byProduct.keys.sorted())")

                    let thirdParty = try #require(byProduct["OldThirdParty"])
                    #expect(thirdParty["package"] as? String == "third-party")
                    #expect(thirdParty["usedBy"] as? [String] == ["Paper"])
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditIncludeTransitiveAddsUnusedDeprecatedProducts(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            // The consumer directly uses PaperLegacy and PaperExperimental. It does
            // NOT depend on paper-tool-old (from producer) or OldThirdParty (from
            // third-party). Both are deprecated products reachable via the graph.
            // With --include-transitive, they must appear in the report with an
            // empty `usedBy` list.
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                try await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--format", "json",
                            "--include-transitive",
                        ],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    let data = Data(error.stdout.utf8)
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let deprecated = root["deprecated"] as? [String: Any],
                          let products = deprecated["products"] as? [[String: Any]] else {
                        Issue.record("audit output is not valid JSON. stdout:\n\(error.stdout)")
                        return
                    }
                    let byProduct = Dictionary(uniqueKeysWithValues: products.compactMap {
                        (product) -> (String, [String: Any])? in
                        guard let name = product["product"] as? String else { return nil }
                        return (name, product)
                    })
                    // All four deprecated products (3 from producer, 1 from third-party)
                    // should now appear.
                    #expect(byProduct.count == 4, "unexpected products: \(byProduct.keys.sorted())")

                    // Directly-consumed products keep their usedBy entries.
                    let paperLegacy = try #require(byProduct["PaperLegacy"])
                    #expect(paperLegacy["usedBy"] as? [String] == ["MyApp"])
                    let experimental = try #require(byProduct["PaperExperimental"])
                    #expect(experimental["usedBy"] as? [String] == ["MyLib"])

                    // Transitively-reachable, not-directly-consumed products have
                    // empty usedBy lists.
                    let tool = try #require(byProduct["paper-tool-old"])
                    #expect(tool["package"] as? String == "producer")
                    #expect(tool["type"] as? String == "executable")
                    #expect(tool["message"] as? String == "Migrate to the standalone paper-tools package.")
                    let toolReplacement = try #require(tool["replacement"] as? [String: Any])
                    #expect(toolReplacement["kind"] as? String == "inPackage")
                    #expect(toolReplacement["package"] as? String == "paper-tools")
                    #expect(toolReplacement["product"] as? String == "paper-tool")
                    #expect(tool["usedBy"] as? [String] == [])

                    let thirdParty = try #require(byProduct["OldThirdParty"])
                    #expect(thirdParty["package"] as? String == "third-party")
                    #expect(thirdParty["type"] as? String == "library")
                    #expect(thirdParty["message"] as? String == "OldThirdParty is unsupported by the third party.")
                    let thirdPartyReplacement = try #require(thirdParty["replacement"] as? [String: Any])
                    #expect(thirdPartyReplacement["kind"] as? String == "renamed")
                    #expect(thirdPartyReplacement["to"] as? String == "NewThirdParty")
                    #expect(thirdParty["usedBy"] as? [String] == [])
                }
            }
        }

        @Test(
            // .requireSwift6_5,
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func auditWithoutIncludeTransitiveOmitsUnusedDeprecatedProducts(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            // Explicit negative counterpart to the --include-transitive test:
            // without the flag, paper-tool-old and OldThirdParty (neither is
            // consumed by any consumer target) must be omitted even though both
            // are reachable via the dependency graph.
            try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                await expectThrowsCommandExecutionError(
                    try await executeSwiftPackage(
                        fixturePath.appending("consumer"),
                        configuration: .debug,
                        extraArgs: [
                            "audit",
                            "--format", "json",
                        ],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    let data = Data(error.stdout.utf8)
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let deprecated = root["deprecated"] as? [String: Any],
                          let products = deprecated["products"] as? [[String: Any]] else {
                        Issue.record("audit output is not valid JSON. stdout:\n\(error.stdout)")
                        return
                    }
                    let names = Set(products.compactMap { $0["product"] as? String })
                    #expect(
                        names.contains("paper-tool-old") == false,
                        "unexpected: \(names)",
                    )
                    #expect(
                        names.contains("OldThirdParty") == false,
                        "unexpected: \(names)",
                    )
                }
            }
        }
    }
}
