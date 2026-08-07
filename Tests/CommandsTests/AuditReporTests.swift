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
    struct AuditReportBuilderTests {

        // MARK: Empty / no deprecations

        @Test
        func report_isEmpty_whenNoDeprecatedProducts() throws {
            let graph = try loadSingleRootGraph(
                withProducts: [
                    try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .off)
            #expect(report.deprecated.products.isEmpty)
        }

        // MARK: --include-transitive off

        @Test
        func report_omitsUnconsumedDeprecatedProduct_whenIncludeTransitiveIsOff() throws {
            // Root package vends a deprecated product but no target in the root
            // package consumes it. With .off, the report is empty.
            let graph = try loadSingleRootGraph(
                withProducts: [
                    try ProductDescription(
                        name: "OldLib",
                        type: .library(.automatic),
                        targets: ["OldLib"],
                        deprecation: ProductDeprecation(
                            message: "gone",
                            replacement: .renamed("NewLib"),
                        ),
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .off)
            #expect(report.deprecated.products.isEmpty)
        }

        @Test
        func report_omitsUnreachableDeprecatedProduct_whenIncludeTransitiveIsReachable() throws {
            // Root package declares a deprecated product but no target
            // consumes it. Since no root-target dependency chain reaches
            // the product, it is transitively unreachable — and `.reachable`
            // mode excludes unreachable entries. Use `.all` (or `.nonReachable`)
            // to surface it.
            let graph = try loadSingleRootGraph(
                withProducts: [
                    try ProductDescription(
                        name: "OldLib",
                        type: .library(.automatic),
                        targets: ["OldLib"],
                        deprecation: ProductDeprecation(
                            message: "gone",
                            replacement: .renamed("NewLib"),
                        ),
                    ),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .reachable)
            #expect(report.deprecated.products.isEmpty)
        }

        // MARK: Direct violations

        @Test
        func report_populatesUsedByAndBreadcrumb_forDirectlyConsumedProduct() throws {
            let graph = try loadConsumerProducerGraph(
                producerProducts: [
                    try ProductDescription(
                        name: "PaperLegacy",
                        type: .library(.automatic),
                        targets: ["PaperLegacy"],
                        deprecation: ProductDeprecation(
                            message: "Use Paper instead.",
                            replacement: .renamed("Paper"),
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
            let report = buildAuditReport(graph: graph, includeTransitive: .off)
            #expect(report.deprecated.products.count == 1)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.product == "PaperLegacy")
            #expect(entry.package == "producer")
            #expect(entry.usedBy == ["MyApp"])
            #expect(entry.transitive == .direct)

            // Breadcrumb: single path with two hops — [target, product].
            let breadcrumb = try #require(entry.breadcrumb)
            #expect(breadcrumb.count == 1)
            let path = try #require(breadcrumb.first)
            #expect(path.count == 2)
            #expect(path[0] == BreadcrumbHop(package: "consumer", target: "MyApp"))
            #expect(path[1] == BreadcrumbHop(package: "producer", product: "PaperLegacy"))
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
            let report = buildAuditReport(graph: graph, includeTransitive: .off)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.usedBy == ["ATarget", "MTarget", "ZTarget"])
            #expect(entry.transitive == .direct)
            // A single deprecated product consumed by three targets: one path
            // per consumer, sorted by consumer name.
            let breadcrumb = try #require(entry.breadcrumb)
            #expect(breadcrumb.count == 3)
            #expect(breadcrumb[0].first == BreadcrumbHop(package: "consumer", target: "ATarget"))
            #expect(breadcrumb[1].first == BreadcrumbHop(package: "consumer", target: "MTarget"))
            #expect(breadcrumb[2].first == BreadcrumbHop(package: "consumer", target: "ZTarget"))
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
            let report = buildAuditReport(graph: graph, includeTransitive: .off)
            #expect(report.deprecated.products.count == 2)
            #expect(report.deprecated.products.map(\.product) == ["Alpha", "Zebra"])
            for entry in report.deprecated.products {
                #expect(
                    entry.transitive == .direct,
                    "product \(entry.product) in package \(entry.package) transitive should be direct",
                )
            }
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
                            replacement: .renamed("new-tool", package: "tools"),
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
            let report = buildAuditReport(graph: graph, includeTransitive: .off)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.type == "executable")
            #expect(entry.transitive == .direct)
            #expect(entry.replacement == .renamed("new-tool", package: "tools"))
        }

        // MARK: --include-transitive reachable

        @Test
        func report_includesReachableDeprecatedProduct_viaNonDeprecatedIntermediate() throws {
            // Root consumer has one target that depends on non-deprecated
            // product 'MidLib' in package 'middle'. MidLib's target depends on
            // deprecated 'Old' in package 'producer'. The deprecated product is
            // transitively reachable — must appear with .transitiveReachable
            // and a breadcrumb of length 3.
            let graph = try loadThreePackageChain(
                rootTarget: TargetDescription(
                    name: "App",
                    dependencies: [.product(name: "MidLib", package: "middle")],
                ),
                middlePackageIdentity: "middle",
                middleProducts: [
                    try ProductDescription(
                        name: "MidLib",
                        type: .library(.automatic),
                        targets: ["MidLib"],
                    ),
                ],
                middleTargets: [
                    TargetDescription(
                        name: "MidLib",
                        dependencies: [.product(name: "Old", package: "producer")],
                    ),
                ],
                leafPackageIdentity: "producer",
                leafProducts: [
                    try ProductDescription(
                        name: "Old",
                        type: .library(.automatic),
                        targets: ["Old"],
                        deprecation: ProductDeprecation(
                            message: "gone",
                            replacement: .renamed("New"),
                        ),
                    ),
                ],
                leafTargets: [TargetDescription(name: "Old")],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .reachable)
            #expect(report.deprecated.products.count == 1)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.product == "Old")
            #expect(entry.package == "producer")
            #expect(entry.transitive == .transitiveReachable)
            #expect(entry.usedBy == ["App"])

            let breadcrumb = try #require(entry.breadcrumb)
            #expect(breadcrumb.count == 1)
            let path = try #require(breadcrumb.first)
            #expect(path.count == 3)
            #expect(path[0] == BreadcrumbHop(package: "consumer", target: "App"))
            #expect(path[1] == BreadcrumbHop(package: "middle", product: "MidLib"))
            #expect(path[2] == BreadcrumbHop(package: "producer", product: "Old"))
        }

        @Test
        func report_reachableMode_omitsUnreachableSiblings() throws {
            // Producer declares two deprecated products: 'Old' (reachable
            // through middle.MidLib) and 'Unrelated' (not on any chain from
            // the root). In .reachable mode, 'Unrelated' must be omitted.
            let graph = try loadThreePackageChain(
                rootTarget: TargetDescription(
                    name: "App",
                    dependencies: [.product(name: "MidLib", package: "middle")],
                ),
                middlePackageIdentity: "middle",
                middleProducts: [
                    try ProductDescription(
                        name: "MidLib",
                        type: .library(.automatic),
                        targets: ["MidLib"],
                    ),
                ],
                middleTargets: [
                    TargetDescription(
                        name: "MidLib",
                        dependencies: [.product(name: "Old", package: "producer")],
                    ),
                ],
                leafPackageIdentity: "producer",
                leafProducts: [
                    try ProductDescription(
                        name: "Old",
                        type: .library(.automatic),
                        targets: ["Old"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                    try ProductDescription(
                        name: "Unrelated",
                        type: .library(.automatic),
                        targets: ["Unrelated"],
                        deprecation: ProductDeprecation(message: "also gone", replacement: nil),
                    ),
                ],
                leafTargets: [
                    TargetDescription(name: "Old"),
                    TargetDescription(name: "Unrelated"),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .reachable)
            #expect(report.deprecated.products.map(\.product) == ["Old"])
        }

        @Test
        func report_multiplePathsToSameProduct_areAllCapturedInBreadcrumb() throws {
            // Two root-package targets (AppA and AppB) both depend on
            // `middle.MidLib`, whose target depends on the deprecated
            // `producer.Old`. The single deprecated product must be
            // reported with a breadcrumb containing TWO paths — one per
            // root consumer — sorted by root target name.
            let fs = InMemoryFileSystem(emptyFiles: [
                "/Consumer/Sources/AppA/source.swift",
                "/Consumer/Sources/AppB/source.swift",
                "/Middle/Sources/MidLib/source.swift",
                "/Producer/Sources/Old/source.swift",
            ])
            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Middle",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "AppA",
                                dependencies: [.product(name: "MidLib", package: "middle")],
                            ),
                            TargetDescription(
                                name: "AppB",
                                dependencies: [.product(name: "MidLib", package: "middle")],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Middle",
                        path: "/Middle",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        products: [
                            try ProductDescription(
                                name: "MidLib",
                                type: .library(.automatic),
                                targets: ["MidLib"],
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "MidLib",
                                dependencies: [.product(name: "Old", package: "producer")],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(message: "gone", replacement: nil),
                            ),
                        ],
                        targets: [TargetDescription(name: "Old")],
                    ),
                ],
                observabilityScope: observability.topScope,
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .reachable)
            #expect(report.deprecated.products.count == 1)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.transitive == .transitiveReachable)
            #expect(entry.usedBy == ["AppA", "AppB"])

            let breadcrumb = try #require(entry.breadcrumb)
            #expect(breadcrumb.count == 2)
            // Paths sorted by root consumer target name.
            #expect(breadcrumb[0] == [
                BreadcrumbHop(package: "consumer", target: "AppA"),
                BreadcrumbHop(package: "middle", product: "MidLib"),
                BreadcrumbHop(package: "producer", product: "Old"),
            ])
            #expect(breadcrumb[1] == [
                BreadcrumbHop(package: "consumer", target: "AppB"),
                BreadcrumbHop(package: "middle", product: "MidLib"),
                BreadcrumbHop(package: "producer", product: "Old"),
            ])
        }

        @Test
        func report_multipleDistinctChains_produceDistinctBreadcrumbPaths() throws {
            // Single root target `App` depends on two non-deprecated
            // intermediate products (`middle.LibA` and `middle.LibB`).
            // Both intermediate targets depend on `producer.Old`
            // (deprecated). The report must contain a single deprecated
            // entry whose breadcrumb has TWO distinct paths differing
            // in the intermediate product hop.
            let fs = InMemoryFileSystem(emptyFiles: [
                "/Consumer/Sources/App/source.swift",
                "/Middle/Sources/LibA/source.swift",
                "/Middle/Sources/LibB/source.swift",
                "/Producer/Sources/Old/source.swift",
            ])
            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "Consumer",
                        path: "/Consumer",
                        dependencies: [
                            .localSourceControl(
                                path: "/Middle",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "App",
                                dependencies: [
                                    .product(name: "LibA", package: "middle"),
                                    .product(name: "LibB", package: "middle"),
                                ],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Middle",
                        path: "/Middle",
                        dependencies: [
                            .localSourceControl(
                                path: "/Producer",
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        products: [
                            try ProductDescription(
                                name: "LibA",
                                type: .library(.automatic),
                                targets: ["LibA"],
                            ),
                            try ProductDescription(
                                name: "LibB",
                                type: .library(.automatic),
                                targets: ["LibB"],
                            ),
                        ],
                        targets: [
                            TargetDescription(
                                name: "LibA",
                                dependencies: [.product(name: "Old", package: "producer")],
                            ),
                            TargetDescription(
                                name: "LibB",
                                dependencies: [.product(name: "Old", package: "producer")],
                            ),
                        ],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: "Producer",
                        path: "/Producer",
                        products: [
                            try ProductDescription(
                                name: "Old",
                                type: .library(.automatic),
                                targets: ["Old"],
                                deprecation: ProductDeprecation(message: "gone", replacement: nil),
                            ),
                        ],
                        targets: [TargetDescription(name: "Old")],
                    ),
                ],
                observabilityScope: observability.topScope,
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .reachable)
            #expect(report.deprecated.products.count == 1)
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.transitive == .transitiveReachable)
            // The consumer target `App` reaches `Old` via two intermediates,
            // but `usedBy` deduplicates on the root-target name.
            #expect(entry.usedBy == ["App"])

            let breadcrumb = try #require(entry.breadcrumb)
            #expect(breadcrumb.count == 2)
            // Paths sorted by intermediate product name (LibA before LibB).
            #expect(breadcrumb[0] == [
                BreadcrumbHop(package: "consumer", target: "App"),
                BreadcrumbHop(package: "middle", product: "LibA"),
                BreadcrumbHop(package: "producer", product: "Old"),
            ])
            #expect(breadcrumb[1] == [
                BreadcrumbHop(package: "consumer", target: "App"),
                BreadcrumbHop(package: "middle", product: "LibB"),
                BreadcrumbHop(package: "producer", product: "Old"),
            ])
        }

        // MARK: --include-transitive all

        @Test
        func report_allMode_reportsDirectReachableAndUnreachable() throws {
            // A direct violation (App → middle.Direct), a reachable
            // transitive (App → middle.MidLib → producer.Reachable), and
            // an unreachable deprecated product (producer.Unreachable, not
            // on any chain from the root).
            //
            // Note: root can only reference products from `middle` directly
            // (the only package it depends on); anything in `producer` must
            // be reached via a middle product.
            let graph = try loadThreePackageChain(
                rootTarget: TargetDescription(
                    name: "App",
                    dependencies: [
                        .product(name: "MidLib", package: "middle"),
                        .product(name: "Direct", package: "middle"),
                    ],
                ),
                middlePackageIdentity: "middle",
                middleProducts: [
                    try ProductDescription(
                        name: "MidLib",
                        type: .library(.automatic),
                        targets: ["MidLib"],
                    ),
                    try ProductDescription(
                        name: "Direct",
                        type: .library(.automatic),
                        targets: ["Direct"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                ],
                middleTargets: [
                    TargetDescription(
                        name: "MidLib",
                        dependencies: [.product(name: "Reachable", package: "producer")],
                    ),
                    TargetDescription(name: "Direct"),
                ],
                leafPackageIdentity: "producer",
                leafProducts: [
                    try ProductDescription(
                        name: "Reachable",
                        type: .library(.automatic),
                        targets: ["Reachable"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                    try ProductDescription(
                        name: "Unreachable",
                        type: .library(.automatic),
                        targets: ["Unreachable"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                ],
                leafTargets: [
                    TargetDescription(name: "Reachable"),
                    TargetDescription(name: "Unreachable"),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .all)
            let byName = Dictionary(uniqueKeysWithValues: report.deprecated.products.map { ($0.product, $0) })
            #expect(byName.count == 3)

            let direct = try #require(byName["Direct"])
            #expect(direct.transitive == .direct)
            let directCrumb = try #require(direct.breadcrumb?.first)
            #expect(directCrumb == [
                BreadcrumbHop(package: "consumer", target: "App"),
                BreadcrumbHop(package: "middle", product: "Direct"),
            ])

            let reachable = try #require(byName["Reachable"])
            #expect(reachable.transitive == .transitiveReachable)
            let reachableCrumb = try #require(reachable.breadcrumb?.first)
            #expect(reachableCrumb == [
                BreadcrumbHop(package: "consumer", target: "App"),
                BreadcrumbHop(package: "middle", product: "MidLib"),
                BreadcrumbHop(package: "producer", product: "Reachable"),
            ])

            let unreachable = try #require(byName["Unreachable"])
            #expect(unreachable.transitive == .transitiveUnreachable)
            #expect(unreachable.usedBy == [])
            // Unreachable entries carry no breadcrumb — no chain to record.
            #expect(unreachable.breadcrumb == nil)
        }

        // MARK: --include-transitive nonReachable

        @Test
        func report_nonReachableMode_omitsDirectAndReachable() throws {
            // Same graph as `report_allMode_...` above — root reaches a direct
            // deprecated `middle.Direct` and a transitive-reachable
            // `producer.Reachable`. `producer.Unreachable` is deprecated but
            // not on any chain. In `.nonReachable` mode only Unreachable
            // survives the filter.
            let graph = try loadThreePackageChain(
                rootTarget: TargetDescription(
                    name: "App",
                    dependencies: [
                        .product(name: "MidLib", package: "middle"),
                        .product(name: "Direct", package: "middle"),
                    ],
                ),
                middlePackageIdentity: "middle",
                middleProducts: [
                    try ProductDescription(
                        name: "MidLib",
                        type: .library(.automatic),
                        targets: ["MidLib"],
                    ),
                    try ProductDescription(
                        name: "Direct",
                        type: .library(.automatic),
                        targets: ["Direct"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                ],
                middleTargets: [
                    TargetDescription(
                        name: "MidLib",
                        dependencies: [.product(name: "Reachable", package: "producer")],
                    ),
                    TargetDescription(name: "Direct"),
                ],
                leafPackageIdentity: "producer",
                leafProducts: [
                    try ProductDescription(
                        name: "Reachable",
                        type: .library(.automatic),
                        targets: ["Reachable"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                    try ProductDescription(
                        name: "Unreachable",
                        type: .library(.automatic),
                        targets: ["Unreachable"],
                        deprecation: ProductDeprecation(message: "gone", replacement: nil),
                    ),
                ],
                leafTargets: [
                    TargetDescription(name: "Reachable"),
                    TargetDescription(name: "Unreachable"),
                ],
            )
            let report = buildAuditReport(graph: graph, includeTransitive: .nonReachable)
            #expect(report.deprecated.products.map(\.product) == ["Unreachable"])
            let entry = try #require(report.deprecated.products.first)
            #expect(entry.transitive == .transitiveUnreachable)
            #expect(entry.usedBy == [])
            #expect(entry.breadcrumb == nil)
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

        /// Builds a three-package graph:
        ///   `Consumer` (root) → `middle` → `<leafPackageIdentity>`
        ///
        /// The root package depends ONLY on `middle`; the leaf package is
        /// reachable only transitively via one of the middle's products.
        /// Callers supply the middle package's products/targets and the leaf
        /// package's products/targets — this permits scenarios where middle
        /// has its own deprecated product (a `.direct` violation) alongside a
        /// non-deprecated product that chains to a deprecated leaf product
        /// (`.transitiveReachable`).
        private func loadThreePackageChain(
            rootTarget: TargetDescription,
            middlePackageIdentity: String,
            middleProducts: [ProductDescription],
            middleTargets: [TargetDescription],
            leafPackageIdentity: String,
            leafProducts: [ProductDescription],
            leafTargets: [TargetDescription],
        ) throws -> ModulesGraph {
            let middleDisplay = middlePackageIdentity.capitalized
            let leafDisplay = leafPackageIdentity.capitalized

            var files: [String] = ["/Consumer/Sources/\(rootTarget.name)/source.swift"]
            for target in middleTargets {
                files.append("/\(middleDisplay)/Sources/\(target.name)/source.swift")
            }
            for target in leafTargets {
                files.append("/\(leafDisplay)/Sources/\(target.name)/source.swift")
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
                                path: AbsolutePath("/\(middleDisplay)"),
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        targets: [rootTarget],
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: middleDisplay,
                        path: AbsolutePath("/\(middleDisplay)"),
                        dependencies: [
                            .localSourceControl(
                                path: AbsolutePath("/\(leafDisplay)"),
                                requirement: .upToNextMajor(from: "1.0.0"),
                            ),
                        ],
                        products: middleProducts,
                        targets: middleTargets,
                    ),
                    Manifest.createFileSystemManifest(
                        displayName: leafDisplay,
                        path: AbsolutePath("/\(leafDisplay)"),
                        products: leafProducts,
                        targets: leafTargets,
                    ),
                ],
                observabilityScope: observability.topScope,
            )
        }
    }

    @Suite
    struct AuditReportProductTypeStringTests {

        @Test
        func productTypeString_mapsSupportedKinds() async throws {
            #expect(auditProductTypeString(.executable) == "executable")
            #expect(auditProductTypeString(.library(.automatic)) == "library")
            #expect(auditProductTypeString(.library(.static)) == "library")
            #expect(auditProductTypeString(.library(.dynamic)) == "library")
            #expect(auditProductTypeString(.plugin) == "plugin")
        }

        @Test
        func productTypeString_returnsNilForUnsupportedKinds() async throws {
            #expect(auditProductTypeString(.test) == nil)
            #expect(auditProductTypeString(.snippet) == nil)
            #expect(auditProductTypeString(.macro) == nil)
        }

    }


    @Suite
    struct AuditReportTextRenderer {

        @Test
        func text_emptyReport_returnsExplicitMessage() async throws {
            let empty = AuditReport(deprecated: .init(products: []))
            #expect(renderAuditReportAsText(empty) == "No deprecated products found.")
        }

        @Test
        func text_directOnly_emitsOnlyDirectSection() async throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "Use Paper.",
                        package: "producer",
                        product: "PaperLegacy",
                        replacement: .renamed("Paper"),
                        type: "library",
                        usedBy: ["MyApp"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "MyApp"),
                            BreadcrumbHop(package: "producer", product: "PaperLegacy"),
                        ]],
                    ),
                ]),
            )
            let expected = """
                Directly consumed deprecated products:
                  package 'producer':
                    library 'PaperLegacy' is unsupported
                      Use Paper.
                      Use 'Paper' instead.
                      Used by: MyApp
                """
            #expect(renderAuditReportAsText(report) == expected)
        }

        @Test
        func text_transitiveReachableOnly_emitsOnlyReachableSection() async throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "PaperExperimental",
                        replacement: nil,
                        type: "library",
                        usedBy: ["MyTransitiveApp"],
                        transitive: .transitiveReachable,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer-transitive", target: "MyTransitiveApp"),
                            BreadcrumbHop(package: "consumer", product: "MyLib"),
                            BreadcrumbHop(package: "producer", product: "PaperExperimental"),
                        ]],
                    ),
                ]),
            )
            let rendered = renderAuditReportAsText(report)
            #expect(rendered.contains("Transitively reachable deprecated products:") == true)
            #expect(rendered.contains("library 'PaperExperimental' is unsupported") == true)
            #expect(rendered.contains("Used by: MyTransitiveApp") == true)
            #expect(rendered.contains("Directly consumed deprecated products:") == false)
            #expect(rendered.contains("Transitively unreachable") == false)
        }

        @Test
        func text_transitiveUnreachableOnly_emitsOnlyUnreachableSection() async throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "Migrate to the standalone paper-tools package.",
                        package: "producer",
                        product: "paper-tool-old",
                        replacement: .renamed("paper-tool", package: "paper-tools"),
                        type: "executable",
                        usedBy: [],
                        transitive: .transitiveUnreachable,
                        breadcrumb: nil,
                    ),
                ]),
            )
            let rendered = renderAuditReportAsText(report)
            #expect(rendered.contains("Transitively unreachable deprecated products:") == true)
            #expect(rendered.contains("executable 'paper-tool-old' is unsupported") == true)
            #expect(rendered.contains("Migrate to the standalone paper-tools package.") == true)
            #expect(rendered.contains("Use 'paper-tool' from package 'paper-tools' instead.") == true)
            #expect(rendered.contains("Directly consumed deprecated products:") == false)
            #expect(rendered.contains("Transitively reachable deprecated products:") == false)
            // Unreachable entries have no 'Used by' line.
            #expect(rendered.contains("Used by:") == false)
        }

        @Test
        func text_allSections_areRenderedInFixedOrder() async throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Direct",
                        replacement: nil,
                        type: "library",
                        usedBy: ["App"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "App"),
                            BreadcrumbHop(package: "producer", product: "Direct"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Reachable",
                        replacement: nil,
                        type: "library",
                        usedBy: ["MidLib"],
                        transitive: .transitiveReachable,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "App"),
                            BreadcrumbHop(package: "middle", product: "MidLib"),
                            BreadcrumbHop(package: "producer", product: "Reachable"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Unreachable",
                        replacement: nil,
                        type: "library",
                        usedBy: [],
                        transitive: .transitiveUnreachable,
                        breadcrumb: nil,
                    ),
                ]),
            )
            let rendered = renderAuditReportAsText(report)
            let directIdx = try #require(rendered.range(of: "Directly consumed deprecated products:"))
            let reachableIdx = try #require(rendered.range(of: "Transitively reachable deprecated products:"))
            let unreachableIdx = try #require(rendered.range(of: "Transitively unreachable deprecated products:"))
            #expect(directIdx != nil)
            #expect(reachableIdx != nil)
            #expect(unreachableIdx != nil)

            #expect(directIdx.lowerBound < reachableIdx.lowerBound)
            #expect(reachableIdx.lowerBound < unreachableIdx.lowerBound)
        }

        @Test
        func text_emptyMessageStringIsSkipped() async throws {
            // An empty (but non-nil) message string is treated the same as
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
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "Consumer"),
                            BreadcrumbHop(package: "producer", product: "Old"),
                        ]],
                    ),
                ]),
            )
            let expected = """
                Directly consumed deprecated products:
                  package 'producer':
                    library 'Old' is unsupported
                      Used by: Consumer
                """
            let actual = renderAuditReportAsText(report)
            #expect(actual == expected)
        }

        @Test
        func text_executableAndPluginProductTypeLabelsAppear() async throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "old-tool",
                        replacement: nil,
                        type: "executable",
                        usedBy: ["Consumer"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "Consumer"),
                            BreadcrumbHop(package: "producer", product: "old-tool"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "OldPlugin",
                        replacement: nil,
                        type: "plugin",
                        usedBy: ["Consumer"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "Consumer"),
                            BreadcrumbHop(package: "producer", product: "OldPlugin"),
                        ]],
                    ),
                ]),
            )
            let rendered = renderAuditReportAsText(report)
            #expect(rendered.contains("executable 'old-tool' is unsupported") == true)
            #expect(rendered.contains("plugin 'OldPlugin' is unsupported") == true)
        }

        @Test
        func text_multipleEntriesGroupedByPackageWithinSection() async throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Alpha",
                        replacement: nil,
                        type: "library",
                        usedBy: ["Consumer"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "Consumer"),
                            BreadcrumbHop(package: "producer", product: "Alpha"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "Beta",
                        replacement: nil,
                        type: "library",
                        usedBy: ["Consumer"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "Consumer"),
                            BreadcrumbHop(package: "producer", product: "Beta"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "third-party",
                        product: "Gamma",
                        replacement: nil,
                        type: "library",
                        usedBy: [],
                        transitive: .transitiveUnreachable,
                        breadcrumb: nil,
                    ),
                ]),
            )
            let expected = """
                Directly consumed deprecated products:
                  package 'producer':
                    library 'Alpha' is unsupported
                      Used by: Consumer
                    library 'Beta' is unsupported
                      Used by: Consumer

                Transitively unreachable deprecated products:
                  package 'third-party':
                    library 'Gamma' is unsupported
                """
            let actual = renderAuditReportAsText(report)
            #expect(actual == expected)
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
                        replacement: .renamed("New"),
                        type: "library",
                        usedBy: ["A", "B"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "A"),
                            BreadcrumbHop(package: "producer", product: "Old"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: "The message",
                        package: "thepackage",
                        product: "deprecatedProductName",
                        replacement: .renamed("New"),
                        type: "executable",
                        usedBy: ["A", "B", "C"],
                        transitive: .transitiveReachable,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "A"),
                            BreadcrumbHop(package: "intermediate", product: "Mid"),
                            BreadcrumbHop(package: "thepackage", product: "deprecatedProductName"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "otherPackage",
                        product: "otherProduct",
                        replacement: nil,
                        type: "plugin",
                        usedBy: [],
                        transitive: .transitiveUnreachable,
                        breadcrumb: nil,
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
                        transitive: .transitiveUnreachable,
                        breadcrumb: nil,
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
        func json_directEntryEmitsTransitiveDirectAndBreadcrumb() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: "m",
                        package: "producer",
                        product: "Old",
                        replacement: .renamed("New"),
                        type: "library",
                        usedBy: ["MyApp"],
                        transitive: .direct,
                        breadcrumb: [
                            [
                                BreadcrumbHop(package: "consumer", target: "MyApp"),
                                BreadcrumbHop(package: "producer", product: "Old"),
                            ],
                        ],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)

            #expect(entry["message"] as? String == "m")
            #expect(entry["package"] as? String == "producer")
            #expect(entry["product"] as? String == "Old")
            #expect(entry["type"] as? String == "library")
            #expect(entry["usedBy"] as? [String] == ["MyApp"])
            #expect(entry["transitive"] as? String == "direct")

            let breadcrumb = try #require(entry["breadcrumb"] as? [[[String: Any]]])
            #expect(breadcrumb.count == 1)
            let path = try #require(breadcrumb.first)
            #expect(path.count == 2)
            #expect(path[0]["package"] as? String == "consumer")
            #expect(path[0]["target"] as? String == "MyApp")
            #expect(path[0]["product"] == nil)
            #expect(path[1]["package"] as? String == "producer")
            #expect(path[1]["product"] as? String == "Old")
            #expect(path[1]["target"] == nil)

            let replacement = try #require(entry["replacement"] as? [String: Any])
            #expect(replacement["kind"] as? String == "renamed")
            #expect(replacement["product"] as? String == "New")
        }

        @Test
        func json_transitiveReachableEntry_hasReachableStringAndBreadcrumb() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "PaperExperimental",
                        replacement: nil,
                        type: "library",
                        usedBy: ["MyTransitiveApp"],
                        transitive: .transitiveReachable,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer-transitive", target: "MyTransitiveApp"),
                            BreadcrumbHop(package: "consumer", product: "MyLib"),
                            BreadcrumbHop(package: "producer", product: "PaperExperimental"),
                        ]],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)
            #expect(entry["transitive"] as? String == "transitiveReachable")
            let breadcrumb = try #require(entry["breadcrumb"] as? [[[String: Any]]])
            let path = try #require(breadcrumb.first)
            #expect(path.count == 3)
        }

        @Test
        func json_transitiveUnreachableEntry_omitsBreadcrumbKey() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "paper-tool-old",
                        replacement: nil,
                        type: "executable",
                        usedBy: [],
                        transitive: .transitiveUnreachable,
                        breadcrumb: nil,
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)
            #expect(entry["transitive"] as? String == "transitiveUnreachable")
            #expect(entry["breadcrumb"] == nil)
            #expect(entry["usedBy"] as? [String] == [])
        }

        @Test
        func json_crossPackageReplacementEmitsPackageAndProductFields() throws {
            let report = AuditReport(
                deprecated: .init(products: [
                    DeprecatedProduct(
                        message: nil,
                        package: "producer",
                        product: "old-tool",
                        replacement: .renamed("new-tool", package: "tools"),
                        type: "executable",
                        usedBy: ["MyApp"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "MyApp"),
                            BreadcrumbHop(package: "producer", product: "old-tool"),
                        ]],
                    ),
                ]),
            )
            let data = try JSONEncoder().encode(report)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let products = try #require((root["deprecated"] as? [String: Any])?["products"] as? [[String: Any]])
            let entry = try #require(products.first)
            let replacement = try #require(entry["replacement"] as? [String: Any])
            #expect(replacement["kind"] as? String == "renamed")
            #expect(replacement["package"] as? String == "tools")
            #expect(replacement["product"] as? String == "new-tool")
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
                        transitive: .direct,
                        breadcrumb: [
                            [
                                BreadcrumbHop(package: "consumer", target: "MyApp"),
                                BreadcrumbHop(package: "producer", product: "Old"),
                            ],
                        ],
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
                        replacement: .renamed("New"),
                        type: "library",
                        usedBy: ["MyApp"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "MyApp"),
                            BreadcrumbHop(package: "producer", product: "Old"),
                        ]],
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
                        replacement: .renamed("New"),
                        type: "library",
                        usedBy: ["MyApp"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "MyApp"),
                            BreadcrumbHop(package: "producer", product: "Old"),
                        ]],
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
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "C"),
                            BreadcrumbHop(package: "aaa", product: "Alpha"),
                        ]],
                    ),
                    DeprecatedProduct(
                        message: nil,
                        package: "bbb",
                        product: "Beta",
                        replacement: nil,
                        type: "library",
                        usedBy: ["C"],
                        transitive: .direct,
                        breadcrumb: [[
                            BreadcrumbHop(package: "consumer", target: "C"),
                            BreadcrumbHop(package: "bbb", product: "Beta"),
                        ]],
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
