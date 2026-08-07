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

import Basics
import Foundation
import PackageModel
import Testing
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

@testable import Commands

/// Pure-logic unit tests for the `swift package audit` report-building and
/// text-rendering helpers. These tests construct in-memory package graphs via
/// `loadModulesGraph` (no `executeSwiftPackage`, no fixture on disk, no swiftc
/// invocation) and assert on `AuditReport` values directly. Complements the
/// end-to-end tests in `PackageCommandTests+Audit.swift`.
@Suite(
    .tags(
        .TestSize.small,
        .Feature.Command.Package.Audit,
        .Feature.Deprecation,
    ),
)
struct AuditReportTests {

    // MARK: - buildAuditReport
    @Suite
    struct AuditReportBuilderTests{
        @Test
        func report_isEmpty_whenNoDeprecatedProducts() throws {
            let graph = try loadSingleRootGraph(
                withProducts: [
                    try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: false)
            #expect(report.deprecated.products.isEmpty)
        }

        @Test
        func report_omitsUnconsumedDeprecatedProduct_whenIncludeTransitiveIsFalse() throws {
            // Root package vends a deprecated product but no target in the root
            // package (or any other package) consumes it. Without
            // --include-transitive, the report is empty.
            let graph = try loadSingleRootGraph(
                withProducts: [
                    try ProductDescription(
                        name: "OldLib",
                        type: .library(.automatic),
                        targets: ["OldLib"],
                        deprecation: ProductDeprecation(
                            message: "gone",
                            replacement: .renamed(to: "NewLib"),
                        ),
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: false)
            #expect(report.deprecated.products.isEmpty)
        }

        @Test
        func report_includesUnconsumedDeprecatedProduct_whenIncludeTransitiveIsTrue() throws {
            let graph = try loadSingleRootGraph(
                withProducts: [
                    try ProductDescription(
                        name: "OldLib",
                        type: .library(.automatic),
                        targets: ["OldLib"],
                        deprecation: ProductDeprecation(
                            message: "gone",
                            replacement: .renamed(to: "NewLib"),
                        ),
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: true)
            #expect(report.deprecated.products.count == 1)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.product == "OldLib")
            #expect(entry.package == "root")
            #expect(entry.type == "library")
            #expect(entry.message == "gone")
            #expect(entry.replacement == .renamed(to: "NewLib"))
            #expect(entry.usedBy == [])
        }

        @Test
        func report_populatesUsedBy_forDirectlyConsumedProduct() throws {
            let graph = try loadConsumerProducerGraph(
                producerProducts: [
                    try ProductDescription(
                        name: "PaperLegacy",
                        type: .library(.automatic),
                        targets: ["PaperLegacy"],
                        deprecation: ProductDeprecation(
                            message: "Use Paper instead.",
                            replacement: .renamed(to: "Paper"),
                        ),
                    ),
                ],
                producerTargets: [
                    TargetDescription(name: "PaperLegacy"),
                ],
                consumerTargets: [
                    TargetDescription(
                        name: "MyApp",
                        dependencies: [
                            .product(name: "PaperLegacy", package: "Producer"),
                        ],
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: false)
            #expect(report.deprecated.products.count == 1)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.product == "PaperLegacy")
            #expect(entry.package == "producer")
            #expect(entry.usedBy == ["MyApp"])
        }

        @Test
        func report_multipleConsumersOfSameProduct_areSortedInUsedBy() throws {
            let graph = try loadConsumerProducerGraph(
                producerProducts: [
                    try ProductDescription(
                        name: "Old",
                        type: .library(.automatic),
                        targets: ["Old"],
                        deprecation: ProductDeprecation(
                            message: "gone",
                            replacement: nil,
                        ),
                    ),
                ],
                producerTargets: [
                    TargetDescription(name: "Old"),
                ],
                consumerTargets: [
                    TargetDescription(
                        name: "ZTarget",
                        dependencies: [.product(name: "Old", package: "Producer")],
                    ),
                    TargetDescription(
                        name: "ATarget",
                        dependencies: [.product(name: "Old", package: "Producer")],
                    ),
                    TargetDescription(
                        name: "MTarget",
                        dependencies: [.product(name: "Old", package: "Producer")],
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: false)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.usedBy == ["ATarget", "MTarget", "ZTarget"])
        }

        @Test
        func report_sortsEntriesByPackageThenProduct() throws {
            let graph = try loadConsumerProducerGraph(
                producerProducts: [
                    try ProductDescription(
                        name: "Zebra",
                        type: .library(.automatic),
                        targets: ["Zebra"],
                        deprecation: ProductDeprecation(message: nil, replacement: nil),
                    ),
                    try ProductDescription(
                        name: "Alpha",
                        type: .library(.automatic),
                        targets: ["Alpha"],
                        deprecation: ProductDeprecation(message: nil, replacement: nil),
                    ),
                ],
                producerTargets: [
                    TargetDescription(name: "Zebra"),
                    TargetDescription(name: "Alpha"),
                ],
                consumerTargets: [
                    TargetDescription(
                        name: "MyApp",
                        dependencies: [
                            .product(name: "Zebra", package: "Producer"),
                            .product(name: "Alpha", package: "Producer"),
                        ],
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: false)
            #expect(report.deprecated.products.count == 2)
            #expect(report.deprecated.products.map(\.product) == ["Alpha", "Zebra"])
        }

        @Test
        func report_capturesReplacementInPackageVariant() throws {
            let graph = try loadConsumerProducerGraph(
                producerProducts: [
                    try ProductDescription(
                        name: "old-tool",
                        type: .executable,
                        targets: ["old-tool"],
                        deprecation: ProductDeprecation(
                            message: "Migrate to new-tool.",
                            replacement: .inPackage(package: "tools", product: "new-tool"),
                        ),
                    ),
                ],
                producerTargets: [
                    TargetDescription(name: "old-tool", type: .executable),
                ],
                consumerTargets: [
                    TargetDescription(
                        name: "Consumer",
                        dependencies: [.product(name: "old-tool", package: "Producer")],
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: false)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.type == "executable")
            #expect(entry.replacement == .inPackage(package: "tools", product: "new-tool"))
        }

        // MARK: - Helpers

        /// Builds a graph containing a single root package with the given products
        /// and a target for each product. No dependencies.
        private func loadSingleRootGraph(
            withProducts products: [ProductDescription],
        ) throws -> ModulesGraph {
            var files: [String] = []
            var targets: [TargetDescription] = []
            for product in products {
                for target in product.targets {
                    files.append("/Root/Sources/\(target)/source.swift")
                    if !targets.contains(where: { $0.name == target }) {
                        targets.append(try TargetDescription(name: target))
                    }
                }
            }
            let fs = InMemoryFileSystem(emptyFiles: files)
            let observability = ObservabilitySystem.makeForTesting()
            return try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Root",
                        path: "/Root",
                        products: products,
                        targets: targets,
                    ),
                ],
                observabilityScope: observability.topScope,
            )
        }

        /// Builds a two-package graph: a `Consumer` root package that depends on
        /// a `Producer` file-system package. Callers supply the producer's products
        /// and targets, and the consumer's targets (which can reference producer's
        /// products via `.product(name:package:)` dependencies).
        private func loadConsumerProducerGraph(
            producerProducts: [ProductDescription],
            producerTargets: [TargetDescription],
            consumerTargets: [TargetDescription],
        ) throws -> ModulesGraph {
            var files: [String] = []
            for target in producerTargets {
                files.append("/Producer/Sources/\(target.name)/source.swift")
            }
            for target in consumerTargets {
                files.append("/Consumer/Sources/\(target.name)/source.swift")
            }
            let fs = InMemoryFileSystem(emptyFiles: files)
            let observability = ObservabilitySystem.makeForTesting()
            return try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: consumerTargets,
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: producerProducts,
                        targets: producerTargets,
                    ),
                ],
                observabilityScope: observability.topScope,
            )
        }
    }

    @Suite
    struct AuditReportProductTypeStringTests {

        @Test
        func productTypeString_mapsSupportedKinds() {
            #expect(auditProductTypeString(.executable) == "executable")
            #expect(auditProductTypeString(.library(.automatic)) == "library")
            #expect(auditProductTypeString(.library(.static)) == "library")
            #expect(auditProductTypeString(.library(.dynamic)) == "library")
            #expect(auditProductTypeString(.plugin) == "plugin")
        }

        @Test
        func productTypeString_returnsNilForUnsupportedKinds() {
            #expect(auditProductTypeString(.test) == nil)
            #expect(auditProductTypeString(.snippet) == nil)
            #expect(auditProductTypeString(.macro) == nil)
        }

    }


    @Suite
    struct AuditReportTextRenderer {
        @Test
        func text_multipleUsedByTargetsAreCommaSeparated() {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Shared",
                        replacement: nil,
                        type: "library",
                        usedBy: ["Alpha", "Beta", "Gamma"],
                    ),
                ]),
            )
            let expected = """
                package 'producer':
                  library 'Shared' is unsupported
                    Used by: Alpha, Beta, Gamma
                """
            let actual = renderAuditReportAsText(report)
            #expect(actual == expected)
        }

        @Test
        func text_executableAndPluginProductTypeLabelsAppear() {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "old-tool",
                        replacement: nil,
                        type: "executable",
                        usedBy: ["Consumer"],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "OldPlugin",
                        replacement: nil,
                        type: "plugin",
                        usedBy: ["Consumer"],
                    ),
                ]),
            )
            let rendered = renderAuditReportAsText(report)
            #expect(rendered.contains("executable 'old-tool' is unsupported") == true)
            #expect(rendered.contains("plugin 'OldPlugin' is unsupported") == true)
        }

        @Test
        func text_emptyMessageStringIsSkipped() {
            // An empty (but non-nil) message string should be treated the same as
            // nil — no message line is emitted.
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "",
                        package: "producer",
                        product: "Old",
                        replacement: nil,
                        type: "library",
                        usedBy: ["Consumer"],
                    ),
                ]),
            )
            let expected = """
                package 'producer':
                  library 'Old' is unsupported
                    Used by: Consumer
                """
            let actual = renderAuditReportAsText(report)
            #expect(
                actual == expected
            )
        }

    @Test
        func text_emptyReport_returnsExplicitMessage() {
            let empty = AuditReport(deprecated: .init(products: []))
            #expect(renderAuditReportAsText(empty) == "No deprecated products found.")
        }

        @Test
        func text_singleEntryWithMessageAndRenamedReplacement() {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "Use Paper.",
                        package: "producer",
                        product: "PaperLegacy",
                        replacement: .renamed(to: "Paper"),
                        type: "library",
                        usedBy: ["MyApp"],
                    ),
                ]),
            )
            let expected = """
                package 'producer':
                  library 'PaperLegacy' is unsupported
                    Use Paper.
                    Use 'Paper' instead.
                    Used by: MyApp
                """
            #expect(renderAuditReportAsText(report) == expected)
        }

        @Test
        func text_entryWithInPackageReplacementAndNoMessage() {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "old-tool",
                        replacement: .inPackage(package: "tools", product: "new-tool"),
                        type: "executable",
                        usedBy: ["Consumer"],
                    ),
                ]),
            )
            let expected = """
                package 'producer':
                  executable 'old-tool' is unsupported
                    Use 'new-tool' from package 'tools' instead.
                    Used by: Consumer
                """
            #expect(renderAuditReportAsText(report) == expected)
        }

        @Test
        func text_entryWithNoMessageAndNoReplacementAndEmptyUsedBy() {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Old",
                        replacement: nil,
                        type: "library",
                        usedBy: [],
                    ),
                ]),
            )
            let expected = """
                package 'producer':
                  library 'Old' is unsupported
                """
            #expect(renderAuditReportAsText(report) == expected)
        }

        @Test
        func text_multipleEntriesGroupedByPackage() {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Alpha",
                        replacement: nil,
                        type: "library",
                        usedBy: ["Consumer"],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Beta",
                        replacement: nil,
                        type: "library",
                        usedBy: ["Consumer"],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "third-party",
                        product: "Gamma",
                        replacement: nil,
                        type: "library",
                        usedBy: [],
                    ),
                ]),
            )
            let expected = """
                package 'producer':
                  library 'Alpha' is unsupported
                    Used by: Consumer
                  library 'Beta' is unsupported
                    Used by: Consumer

                package 'third-party':
                  library 'Gamma' is unsupported
                """
            #expect(renderAuditReportAsText(report) == expected)
        }
    }

    @Suite
    struct AuditReportCodableTests {

        @Test
        func report_roundTripsThroughJSON() throws {
            let original = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "Use New.",
                        package: "producer",
                        product: "Old",
                        replacement: .renamed(to: "New"),
                        type: "library",
                        usedBy: ["A", "B"],
                    ),
                    DeprecatedProduct(
                        message: "The message",
                        package: "thepackage",
                        product: "deprecatedProductName",
                        replacement: .renamed(to: "New"),
                        type: "exeuctable",
                        usedBy: ["A", "B", "C"],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "otherPackage",
                        product: "otherProduct",
                        replacement: nil,
                        type: "plugin",
                        usedBy: ["Foo", "Bar", "Baz"],
                    ),

                ]),
            )
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AuditReport.self, from: encoded)
            #expect(decoded == original)
        }

        @Test
        func json_emptyReport_hasCanonicalShape() throws {
            let empty = AuditReport(deprecated: .init(products: []))
            let encoder = JSONEncoder()
            encoder.outputFormatting.insert(.sortedKeys)
            let data = try encoder.encode(empty)
            let jsonString = String(decoding: data, as: UTF8.self)
            // Sorted keys → the two keys serialize in stable alphabetical order.
            #expect(jsonString == #"{"deprecated":{"products":[]}}"#)
        }

        @Test
        func json_topLevelHasDeprecatedProductsKey() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "p",
                        product: "q",
                        replacement: nil,
                        type: "library",
                        usedBy: [],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let deprecated = try #require(root["deprecated"] as? [String: Any])
            let products = try #require(deprecated["products"] as? [[String: Any]])
            #expect(products.count == 1)
        }

        @Test
        func json_entryUsesSchemaMandatedKeyNames() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "m",
                        package: "producer",
                        product: "Old",
                        replacement: .renamed(to: "New"),
                        type: "library",
                        usedBy: ["MyApp"],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)

            // Keys required by the proposal's JSON schema.
            #expect(entry["message"] as? String == "m")
            #expect(entry["package"] as? String == "producer")
            #expect(entry["product"] as? String == "Old")
            #expect(entry["type"] as? String == "library")
            #expect(entry["usedBy"] as? [String] == ["MyApp"])
            let replacement = try #require(entry["replacement"] as? [String: Any])
            #expect(replacement["kind"] as? String == "renamed")
            #expect(replacement["to"] as? String == "New")
        }

        @Test
        func json_inPackageReplacementEmitsPackageAndProductFields() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "old-tool",
                        replacement: .inPackage(package: "tools", product: "new-tool"),
                        type: "executable",
                        usedBy: ["MyApp"],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)
            let replacement = try #require(entry["replacement"] as? [String: Any])
            #expect(replacement["kind"] as? String == "inPackage")
            #expect(replacement["package"] as? String == "tools")
            #expect(replacement["product"] as? String == "new-tool")
            #expect(replacement["to"] == nil)
        }

        @Test
        func json_nilReplacementOmitsReplacementKey() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "gone",
                        package: "producer",
                        product: "Old",
                        replacement: nil,
                        type: "library",
                        usedBy: ["MyApp"],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)
            #expect(entry["replacement"] == nil)
        }

        @Test
        func json_nilMessageOmitsMessageKey() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Old",
                        replacement: .renamed(to: "New"),
                        type: "library",
                        usedBy: ["MyApp"],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)
            #expect(entry["message"] == nil)
        }

        @Test
        func json_sortedKeysProducesByteStableOutput() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "m",
                        package: "producer",
                        product: "Old",
                        replacement: .renamed(to: "New"),
                        type: "library",
                        usedBy: ["MyApp"],
                    ),
                ]),
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting.insert(.sortedKeys)

            // Two independent encodes with sortedKeys must produce identical bytes,
            // regardless of dictionary iteration order.
            let first = try encoder.encode(report)
            let second = try encoder.encode(report)
            #expect(first == second)

            // Additionally verify the top-level object's keys are in alphabetical
            // order (a schema requirement — audit-v1 says sorted keys at every
            // nesting level).
            let jsonString = String(decoding: first, as: UTF8.self)
            let deprecatedIndex = try #require(jsonString.range(of: "\"deprecated\""))
            #expect(jsonString[..<deprecatedIndex.lowerBound] == "{")
        }

        @Test
        func json_multipleEntriesArraySortIsPreserved() throws {
            // The encoder does not re-sort array elements; whatever order
            // `buildAuditReport` places entries in is preserved on the wire.
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "aaa",
                        product: "Alpha",
                        replacement: nil,
                        type: "library",
                        usedBy: ["C"],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "bbb",
                        product: "Beta",
                        replacement: nil,
                        type: "library",
                        usedBy: ["C"],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let names = products.compactMap { $0["product"] as? String }
            #expect(names == ["Alpha", "Beta"])
        }
    }
}
