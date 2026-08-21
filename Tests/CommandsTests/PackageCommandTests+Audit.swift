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

        // MARK: - Direct violations (transitive == "direct")

        @Suite
        struct DirectViolationsTests {
            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditReportsDirectDeprecatedProductsInJson(
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
                        let data = Data(error.stdout.utf8)
                        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let deprecated = root["deprecated"] as? [String: Any],
                              let products = deprecated["products"] as? [[String: Any]] else {
                            Issue.record("audit output is not valid JSON. stdout:\n\(error.stdout)")
                            return
                        }
                        // consumer's MyApp directly consumes PaperLegacy;
                        // MyLib directly consumes PaperExperimental. Both are
                        // deprecated. Nothing else is reachable, so no
                        // transitive entries appear (--include-transitive not
                        // passed).
                        #expect(products.count == 2, "unexpected products: \(products.map { $0["product"] as? String ?? "?" })")

                        let byProduct = Dictionary(uniqueKeysWithValues: products.compactMap {
                            (product) -> (String, [String: Any])? in
                            guard let name = product["product"] as? String else { return nil }
                            return (name, product)
                        })

                        let paperLegacy = try #require(byProduct["PaperLegacy"])
                        #expect(paperLegacy["package"] as? String == "producer")
                        #expect(paperLegacy["type"] as? String == "library")
                        #expect(paperLegacy["transitive"] as? String == "direct")
                        #expect(paperLegacy["message"] as? String == "PaperLegacy is superseded by Paper.")
                        let paperLegacyReplacement = try #require(paperLegacy["replacement"] as? [String: Any])
                        #expect(paperLegacyReplacement["kind"] as? String == "renamed")
                        #expect(paperLegacyReplacement["product"] as? String == "Paper")
                        #expect(paperLegacy["usedBy"] as? [String] == ["MyApp"])
                        // Direct entries carry a breadcrumb: [target-hop, product-hop].
                        let paperLegacyBreadcrumb = try #require(paperLegacy["breadcrumb"] as? [[[String: Any]]])
                        #expect(paperLegacyBreadcrumb.count == 1)
                        let paperLegacyPath = try #require(paperLegacyBreadcrumb.first)
                        #expect(paperLegacyPath.count == 2)
                        #expect(paperLegacyPath[0]["package"] as? String == "consumer")
                        #expect(paperLegacyPath[0]["target"] as? String == "MyApp")
                        #expect(paperLegacyPath[1]["package"] as? String == "producer")
                        #expect(paperLegacyPath[1]["product"] as? String == "PaperLegacy")

                        let experimental = try #require(byProduct["PaperExperimental"])
                        #expect(experimental["type"] as? String == "library")
                        #expect(experimental["transitive"] as? String == "direct")
                        #expect(experimental["message"] as? String == "PaperExperimental is going away with no replacement.")
                        #expect(experimental["replacement"] == nil)
                        #expect(experimental["usedBy"] as? [String] == ["MyLib"])
                        let experimentalBreadcrumb = try #require(experimental["breadcrumb"] as? [[[String: Any]]])
                        #expect(experimentalBreadcrumb.count == 1)
                        let experimentalPath = try #require(experimentalBreadcrumb.first)
                        #expect(experimentalPath.count == 2)
                        #expect(experimentalPath[0]["package"] as? String == "consumer")
                        #expect(experimentalPath[0]["target"] as? String == "MyLib")
                        #expect(experimentalPath[1]["package"] as? String == "producer")
                        #expect(experimentalPath[1]["product"] as? String == "PaperExperimental")
                    }
                }
            }

            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditReportsDirectDeprecatedProductsInText(
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
                            error.stdout.contains("Directly consumed deprecated products:") == true,
                            "stderr:\n\(error.stderr)",
                        )
                        #expect(
                            error.stdout.contains("PaperLegacy") == true,
                            "stderr:\n\(error.stderr)",
                        )
                        #expect(
                            error.stdout.contains("PaperLegacy is superseded by Paper.") == true,
                            "stderr:\n\(error.stderr)",
                        )
                        #expect(
                            error.stdout.contains("Use 'Paper' instead.") == true,
                            "stderr:\n\(error.stderr)",
                        )
                        #expect(
                            error.stdout.contains("PaperExperimental") == true,
                            "stderr:\n\(error.stderr)",
                        )
                        #expect(
                            error.stdout.contains("PaperExperimental is going away with no replacement.") == true,
                            "stderr:\n\(error.stderr)",
                        )
                        // Nothing transitively reachable or unreachable is
                        // included without --include-transitive.
                        #expect(
                            error.stdout.contains("Transitively reachable") == false,
                            "unexpected transitive-reachable section:\n\(error.stderr)",
                        )
                        #expect(
                            error.stdout.contains("Transitively unreachable") == false,
                            "unexpected transitive-unreachable section:\n\(error.stderr)",
                        )
                    }
                }
            }
        }

        // MARK: - Exit-code semantics

        @Suite
        struct ExitCodeSemanticsTests {
            @Test(
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
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditRejectsInvalidFormat(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await #expect(throws: (any Error).self) {
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
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditRejectsInvalidIncludeTransitiveMode(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await #expect(throws: (any Error).self) {
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer"),
                            configuration: .debug,
                            extraArgs: [
                                "audit",
                                "--include-transitive=bogus",
                            ],
                            buildSystem: buildSystem,
                        )
                    }
                }
            }
        }

        // MARK: - Clean package (empty report)

        @Suite
        struct CleanPackageTests {
            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditOnCleanPackageEmitsEmptyReport(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // Auditing `producer` directly: no producer target has a
                // `.product(...)` dependency on any deprecated product, so
                // there are no direct violations. Its own deprecated products
                // (paper-tool-old, PaperLegacy, PaperExperimental) exist in the
                // graph but are unreachable — without --include-transitive
                // they're omitted.
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    let (stdout, _) = try await executeSwiftPackage(
                        fixturePath.appending("producer"),
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
        }

        // MARK: - Transitive reachable violations (transitive == "transitiveReachable")

        @Suite
        struct TransitiveReachableViolationsTests {
            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditOnConsumerTransitiveReportsNothingByDefault(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // `consumer-transitive` has one target (MyTransitiveApp) that
                // depends on `.product("MyLib", package: "consumer")`. `MyLib`
                // is NOT deprecated, so no direct violations. Without
                // --include-transitive, its transitively-reachable deprecated
                // product (PaperExperimental) is omitted → empty report.
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    let (stdout, _) = try await executeSwiftPackage(
                        fixturePath.appending("consumer-transitive"),
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
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditOnConsumerTransitiveWithBareIncludeTransitiveReportsReachable(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // Bare `--include-transitive` (no value) defaults to
                // "reachable" mode. PaperExperimental is transitively
                // reachable via MyTransitiveApp → MyLib →
                // .product(PaperExperimental, ...).
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await expectThrowsCommandExecutionError(
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer-transitive"),
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
                        #expect(products.count == 1, "unexpected products: \(products.map { $0["product"] as? String ?? "?" })")

                        let entry = try #require(products.first)
                        #expect(entry["product"] as? String == "PaperExperimental")
                        #expect(entry["package"] as? String == "producer")
                        #expect(entry["transitive"] as? String == "transitiveReachable")
                        #expect(entry["usedBy"] as? [String] == ["MyTransitiveApp"])
                        // Breadcrumb: MyTransitiveApp (target) → consumer.MyLib
                        // (product) → producer.PaperExperimental (product).
                        let breadcrumb = try #require(entry["breadcrumb"] as? [[[String: Any]]])
                        let path = try #require(breadcrumb.first)
                        #expect(path.count == 3)
                        #expect(path[0]["package"] as? String == "consumer-transitive")
                        #expect(path[0]["target"] as? String == "MyTransitiveApp")
                        #expect(path[1]["package"] as? String == "consumer")
                        #expect(path[1]["product"] as? String == "MyLib")
                        #expect(path[2]["package"] as? String == "producer")
                        #expect(path[2]["product"] as? String == "PaperExperimental")
                    }
                }
            }

            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditIncludeTransitiveEqualsReachableIsSameAsBare(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // `--include-transitive=reachable` is the explicit form of the
                // bare flag; must produce the same report.
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await expectThrowsCommandExecutionError(
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer-transitive"),
                            configuration: .debug,
                            extraArgs: [
                                "audit",
                                "--format", "json",
                                "--include-transitive=reachable",
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
                        #expect(products.count == 1)
                        let entry = try #require(products.first)
                        #expect(entry["transitive"] as? String == "transitiveReachable")
                        #expect(entry["product"] as? String == "PaperExperimental")
                    }
                }
            }

            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditOnConsumerTransitiveTextEmitsReachableSection(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    await expectThrowsCommandExecutionError(
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer-transitive"),
                            configuration: .debug,
                            extraArgs: [
                                "audit",
                                "--format", "text",
                                "--include-transitive",
                            ],
                            buildSystem: buildSystem,
                        )
                    ) { error in
                        #expect(
                            error.stdout.contains("Transitively reachable deprecated products:"),
                            "stdout:\n\(error.stdout)",
                        )
                        #expect(
                            error.stdout.contains("PaperExperimental"),
                            "stdout:\n\(error.stdout)",
                        )
                        // No direct violations on consumer-transitive.
                        #expect(
                            !error.stdout.contains("Directly consumed deprecated products:"),
                            "unexpected direct section:\n\(error.stdout)",
                        )
                        // Not in "all" mode → no unreachable section.
                        #expect(
                            !error.stdout.contains("Transitively unreachable"),
                            "unexpected unreachable section:\n\(error.stdout)",
                        )
                    }
                }
            }
        }

        // MARK: - Transitive unreachable violations (transitive == "transitiveUnreachable")

        @Suite
        struct TransitiveUnreachableViolationsTests {
            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditWithIncludeTransitiveAllReportsUnreachableOnConsumer(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // Auditing `consumer` with --include-transitive=all: MyApp and
                // MyLib produce direct violations for PaperLegacy and
                // PaperExperimental. `paper-tool-old` is deprecated in
                // producer, is in the resolved graph, and no consumer target
                // reaches it → surfaces as "transitiveUnreachable".
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await expectThrowsCommandExecutionError(
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer"),
                            configuration: .debug,
                            extraArgs: [
                                "audit",
                                "--format", "json",
                                "--include-transitive=all",
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
                        #expect(byProduct.count == 3, "unexpected products: \(byProduct.keys.sorted())")

                        let legacy = try #require(byProduct["PaperLegacy"])
                        #expect(legacy["transitive"] as? String == "direct")

                        let experimental = try #require(byProduct["PaperExperimental"])
                        #expect(experimental["transitive"] as? String == "direct")

                        let tool = try #require(byProduct["paper-tool-old"])
                        #expect(tool["transitive"] as? String == "transitiveUnreachable")
                        #expect(tool["package"] as? String == "producer")
                        #expect(tool["type"] as? String == "executable")
                        #expect(tool["message"] as? String == "Migrate to the standalone paper-tools package.")
                        let toolReplacement = try #require(tool["replacement"] as? [String: Any])
                        #expect(toolReplacement["kind"] as? String == "renamed")
                        #expect(toolReplacement["package"] as? String == "paper-tools")
                        #expect(toolReplacement["product"] as? String == "paper-tool")
                        // Empty usedBy for unreachable entries.
                        #expect(tool["usedBy"] as? [String] == [])
                        // Unreachable entries have no breadcrumb.
                        #expect(tool["breadcrumb"] == nil)
                    }
                }
            }

            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditWithIncludeTransitiveNonReachableSkipsReachable(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // Auditing `consumer-transitive` with
                // --include-transitive=non-reachable: PaperExperimental is
                // reachable via MyTransitiveApp → consumer.MyLib → producer.
                // PaperExperimental, so it MUST be omitted. paper-tool-old
                // and PaperLegacy are unreachable from consumer-transitive
                // (PaperLegacy is only consumed by consumer.MyApp, which is
                // not on any chain from consumer-transitive), so both MUST
                // be included as `transitiveUnreachable`.
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await expectThrowsCommandExecutionError(
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer-transitive"),
                            configuration: .debug,
                            extraArgs: [
                                "audit",
                                "--format", "json",
                                "--include-transitive=non-reachable",
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

                        let names = Set(products.compactMap { $0["product"] as? String })
                        #expect(
                            names == ["paper-tool-old", "PaperLegacy"],
                            "unexpected names: \(names)",
                        )

                        // PaperExperimental is reachable — skipped.
                        #expect(byProduct["PaperExperimental"] == nil)
                        // paper-tool-old is unreachable — included.
                        let tool = try #require(byProduct["paper-tool-old"])
                        #expect(tool["transitive"] as? String == "transitiveUnreachable")
                        #expect(tool["usedBy"] as? [String] == [])
                        #expect(tool["breadcrumb"] == nil)
                        // PaperLegacy is also unreachable from consumer-transitive
                        // (only consumer.MyApp reaches it, and MyApp isn't on
                        // any chain from consumer-transitive).
                        let legacy = try #require(byProduct["PaperLegacy"])
                        #expect(legacy["transitive"] as? String == "transitiveUnreachable")
                        #expect(legacy["usedBy"] as? [String] == [])
                        #expect(legacy["breadcrumb"] == nil)
                    }
                }
            }

            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditIncludeTransitiveReachableOmitsUnreachable(
                buildSystem: BuildSystemProvider.Kind,
            ) async throws {
                // Auditing `consumer-transitive` with
                // --include-transitive=reachable: only `PaperExperimental`
                // is reachable (via MyTransitiveApp → consumer.MyLib →
                // producer.PaperExperimental). PaperLegacy and paper-tool-old
                // are unreachable from consumer-transitive and MUST be
                // omitted. MyLib is not deprecated so it doesn't appear at all.
                try await fixture(name: "Miscellaneous/DeprecatedProducts/") { fixturePath in
                    try await expectThrowsCommandExecutionError(
                        try await executeSwiftPackage(
                            fixturePath.appending("consumer-transitive"),
                            configuration: .debug,
                            extraArgs: [
                                "audit",
                                "--format", "json",
                                "--include-transitive=reachable",
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
                            names == ["PaperExperimental"],
                            "unexpected products: \(names)",
                        )
                    }
                }
            }

            @Test(
                arguments: SupportedBuildSystemOnAllPlatforms,
            )
            func auditWithIncludeTransitiveAllTextEmitsUnreachableSection(
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
                                "--include-transitive=all",
                            ],
                            buildSystem: buildSystem,
                        )
                    ) { error in
                        #expect(
                            error.stdout.contains("Directly consumed deprecated products:") == true,
                            "stdout:\n\(error.stdout)",
                        )
                        #expect(
                            error.stdout.contains("Transitively unreachable deprecated products:") == true,
                            "stdout:\n\(error.stdout)",
                        )
                        #expect(
                            error.stdout.contains("paper-tool-old") == true,
                            "stdout:\n\(error.stdout)",
                        )
                    }
                }
            }
        }
    }
}
