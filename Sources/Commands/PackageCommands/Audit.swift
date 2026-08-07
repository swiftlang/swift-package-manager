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

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel

struct Audit: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Report deprecated products in the current package graph.",
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Option(help: "Set the output format ('text' or 'json').")
    var format: AuditFormat = .text

    @Option(
        name: .customLong("include-transitive"),
        defaultAsFlag: IncludeTransitive.reachable,
        help: ArgumentHelp(
            "Report deprecated products reached only transitively (via a non-deprecated product's own dependencies).",
            discussion: "Bare '--include-transitive' selects 'reachable'. Explicit values: 'reachable', 'all', 'non-reachable'.",
        ),
    )
    var includeTransitiveMode: IncludeTransitive? = nil

    @Flag(
        name: .customLong("allow-deprecations"),
        help: "Exit with status 0 even when deprecated products are found.",
    )
    var allowDeprecations: Bool = false

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        // Audit produces its own structured deprecation report — suppress the
        // graph-load-time deprecation warnings/errors so they don't duplicate
        // (or, when a consumer target has `.treatAllWarnings(.error)`, prevent
        // the load from completing at all). `exitOnError: false` is likewise
        // required so a per-target escalation of another consumer's warning
        // does not halt the load before this command can print its report.
        let graph = try await swiftCommandState.loadPackageGraph(
            explicitProduct: nil,
            enableAllTraits: false,
            testEntryPointPath: nil,
            exitOnError: false,
            emitProductDeprecationDiagnostics: false,
        )
        let report = buildAuditReport(
            graph: graph,
            includeTransitive: self.includeTransitiveMode ?? .off,
        )

        switch self.format {
        case .text:
            print(renderAuditReportAsText(report))
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting.insert(.sortedKeys)
            encoder.outputFormatting.insert(.prettyPrinted)
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        }

        if report.hasViolations && !self.allowDeprecations {
            throw ExitCode(1)
        }
    }

    // MARK: - Model

    enum AuditFormat: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
        case text, json

        init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "text":
                self = .text
            case "json":
                self = .json
            default:
                return nil
            }
        }

        var description: String {
            switch self {
            case .text: return "text"
            case .json: return "json"
            }
        }
    }
}

// MARK: - `--include-transitive` mode

/// Filter applied to the audit report.
///
/// * `.off` (default when the flag is absent) — only direct violations.
/// * `.reachable` (bare `--include-transitive` or `=reachable`) — direct
///   plus transitively reachable violations.
/// * `.all` (`=all`) — direct + reachable + unreachable.
/// * `.nonReachable` (`=non-reachable`) — unreachable only.
enum IncludeTransitive: String, CaseIterable, ExpressibleByArgument {
    case off
    case reachable
    case all
    case nonReachable = "non-reachable"

    // `.off` is an internal-only sentinel — it can never come in from the CLI.
    static var allValueStrings: [String] {
        Self.allCases.compactMap { $0 == .off ? nil : $0.rawValue }
    }

    init?(argument: String) {
        guard argument != IncludeTransitive.off.rawValue else { return nil }
        self.init(rawValue: argument)
    }
}

// MARK: - Report model (internal so unit tests can construct + assert)

struct AuditReport: Codable, Equatable {
    struct Deprecated: Codable, Equatable {
        var products: [DeprecatedProduct]
    }

    var deprecated: Deprecated
}

struct DeprecatedProduct: Codable, Equatable {
    /// Classification of how (or whether) the deprecated product is reached
    /// from any root-package target. Serialized as a string; matches the JSON
    /// schema in the proposal.
    enum Transitive: String, Codable {
        case direct
        case transitiveReachable
        case transitiveUnreachable
    }

    var message: String?
    var package: String
    var product: String
    var replacement: ProductDeprecation.Replacement?
    var type: String
    var usedBy: [String]
    var transitive: Transitive
    /// Sequence(s) of hops from a root-package target down to the deprecated
    /// product. `nil` (omitted from JSON) for `.transitiveUnreachable` entries.
    var breadcrumb: [[BreadcrumbHop]]?
}

/// A single step in a breadcrumb path. The first hop of a path always names a
/// root-package target (`target` populated, `product` nil); every subsequent
/// hop names a product-boundary crossing (`product` populated, `target` nil).
struct BreadcrumbHop: Codable, Equatable {
    var package: String
    var target: String?
    var product: String?

    init(package: String, target: String? = nil, product: String? = nil) {
        self.package = package
        self.target = target
        self.product = product
    }
}

struct ProductKey: Hashable {
    let package: String
    let product: String
}

// MARK: - Pure report-building logic (internal for testability)

/// Walks the resolved graph and produces an audit report of deprecated products.
///
/// - Parameters:
///   - graph: The resolved package graph to inspect.
///   - includeTransitive: Filter mode. See `IncludeTransitive` for semantics.
/// - Returns: An `AuditReport` with products sorted by `(package, product)`
///   for deterministic output.
func buildAuditReport(
    graph: ModulesGraph,
    includeTransitive: IncludeTransitive,
) -> AuditReport {
    // 1. Enumerate every deprecated product in the resolved graph. We match
    //    them by (packageIdentity, productName) since the same product name
    //    in two different packages is distinct.
    var deprecatedProducts: [ProductKey: ResolvedProduct] = [:]
    for product in graph.allProducts {
        guard product.underlying.deprecation != nil else { continue }
        guard auditProductTypeString(product.type) != nil else { continue }
        let key = ProductKey(
            package: product.packageIdentity.description,
            product: product.name,
        )
        deprecatedProducts[key] = product
    }

    // 2. BFS on the target-dependency graph starting from each root-package
    //    target. Every `.product(...)` edge we traverse contributes a hop to
    //    the current breadcrumb. When we cross into a deprecated product we
    //    record the path (and stop — we don't recurse into the deprecated
    //    product's own dependencies).
    var reachedPaths: [ProductKey: [[BreadcrumbHop]]] = [:]
    var reachedRootTargets: [ProductKey: Set<String>] = [:]

    for rootPackage in graph.rootPackages {
        for rootTarget in rootPackage.modules {
            let rootHop = BreadcrumbHop(
                package: rootPackage.identity.description,
                target: rootTarget.name,
            )
            walkFromRootTarget(
                rootTarget: rootTarget,
                rootHop: rootHop,
                rootTargetName: rootTarget.name,
                deprecatedProducts: deprecatedProducts,
                reachedPaths: &reachedPaths,
                reachedRootTargets: &reachedRootTargets,
            )
        }
    }

    // 3. Assemble entries. Classify each product by whether it was reached
    //    directly (any path of length 2 = root-target-hop +
    //    deprecated-product-hop) or only transitively (all paths longer than
    //    2). Products that were never reached are `.transitiveUnreachable`.
    var entries: [DeprecatedProduct] = []
    for (key, product) in deprecatedProducts {
        guard let typeString = auditProductTypeString(product.type) else { continue }

        let deprecation = product.underlying.deprecation
        let rawPaths = reachedPaths[key] ?? []
        let paths = deduplicateAndSortBreadcrumbPaths(rawPaths)
        let usedBy = (reachedRootTargets[key] ?? []).sorted()

        let transitive: DeprecatedProduct.Transitive
        let breadcrumb: [[BreadcrumbHop]]?
        if paths.isEmpty {
            transitive = .transitiveUnreachable
            breadcrumb = nil
        } else {
            transitive = paths.contains(where: { $0.count == 2 }) ? .direct : .transitiveReachable
            breadcrumb = paths
        }

        // Apply the filter mode.
        switch (includeTransitive, transitive) {
        case (.off, .direct):
            break
        case (.off, _):
            continue
        case (.reachable, .transitiveUnreachable):
            continue
        case (.reachable, _):
            break
        case (.nonReachable, .transitiveUnreachable):
            break
        case (.nonReachable, _):
            continue
        case (.all, _):
            break
        }

        entries.append(
            DeprecatedProduct(
                message: deprecation?.message,
                package: key.package,
                product: key.product,
                replacement: deprecation?.replacement,
                type: typeString,
                usedBy: usedBy,
                transitive: transitive,
                breadcrumb: breadcrumb,
            )
        )
    }

    entries.sort { lhs, rhs in
        if lhs.package != rhs.package {
            return lhs.package < rhs.package
        }
        return lhs.product < rhs.product
    }

    return AuditReport(deprecated: .init(products: entries))
}

/// BFS from a single root-package target. Visited-set is on `(target,
/// breadcrumb-length)` so we don't loop forever, but distinct paths to the
/// same deprecated product are recorded separately.
private func walkFromRootTarget(
    rootTarget: ResolvedModule,
    rootHop: BreadcrumbHop,
    rootTargetName: String,
    deprecatedProducts: [ProductKey: ResolvedProduct],
    reachedPaths: inout [ProductKey: [[BreadcrumbHop]]],
    reachedRootTargets: inout [ProductKey: Set<String>],
) {
    struct Frame {
        let module: ResolvedModule
        let breadcrumb: [BreadcrumbHop]
    }
    var queue: [Frame] = [Frame(module: rootTarget, breadcrumb: [rootHop])]
    // Guard against traversal cycles within the target-dependency graph. A
    // module can legitimately appear on multiple *distinct* paths (that's
    // what produces multi-path breadcrumbs), so the visited key is the
    // (module, breadcrumb-of-product-hops) pair — not just the module.
    var visited: Set<String> = []
    while !queue.isEmpty {
        let frame = queue.removeFirst()
        let productHopsKey = frame.breadcrumb.dropFirst()
            .map { "\($0.package)/\($0.product ?? "")" }
            .joined(separator: "→")
        let visitKey = "\(frame.module.packageIdentity)/\(frame.module.name)|\(productHopsKey)"
        if visited.contains(visitKey) { continue }
        visited.insert(visitKey)

        for dependency in frame.module.dependencies {
            switch dependency {
            case .module(let dependee, _):
                // Same-package target dep: no hop added, just keep walking.
                queue.append(Frame(module: dependee, breadcrumb: frame.breadcrumb))
            case .product(let dependeeProduct, _):
                let key = ProductKey(
                    package: dependeeProduct.packageIdentity.description,
                    product: dependeeProduct.name,
                )
                let productHop = BreadcrumbHop(
                    package: dependeeProduct.packageIdentity.description,
                    product: dependeeProduct.name,
                )
                let extendedBreadcrumb = frame.breadcrumb + [productHop]

                if deprecatedProducts[key] != nil {
                    // Reached a deprecated product — record the path and stop
                    // descending. (Consumers don't care about deps *of* a
                    // deprecated product for audit purposes.)
                    reachedPaths[key, default: []].append(extendedBreadcrumb)
                    reachedRootTargets[key, default: []].insert(rootTargetName)
                } else {
                    // Non-deprecated intermediate — enter each of the
                    // product's constituent modules with the extended
                    // breadcrumb.
                    for member in dependeeProduct.modules {
                        queue.append(Frame(module: member, breadcrumb: extendedBreadcrumb))
                    }
                }
            }
        }
    }
}

/// Order breadcrumb paths deterministically: element-wise by (target-or-product
/// name) so that a stable sort emerges regardless of graph-walk order.
private func compareBreadcrumbPaths(_ lhs: [BreadcrumbHop], _ rhs: [BreadcrumbHop]) -> Bool {
    for (l, r) in zip(lhs, rhs) {
        let lName = l.target ?? l.product ?? ""
        let rName = r.target ?? r.product ?? ""
        if lName != rName { return lName < rName }
        if l.package != r.package { return l.package < r.package }
    }
    return lhs.count < rhs.count
}

/// The same product can be reached from a single root target via multiple
/// same-package `.target(...)` chains that collapse to identical product-hop
/// sequences. Those are indistinguishable in the audit's product-oriented
/// breadcrumb, so we deduplicate here rather than surface duplicates.
private func deduplicateAndSortBreadcrumbPaths(_ paths: [[BreadcrumbHop]]) -> [[BreadcrumbHop]] {
    var seen: Set<String> = []
    var unique: [[BreadcrumbHop]] = []
    for path in paths {
        let key = path
            .map { "\($0.package)/\($0.target ?? "")|\($0.product ?? "")" }
            .joined(separator: "→")
        if seen.insert(key).inserted {
            unique.append(path)
        }
    }
    return unique.sorted(by: compareBreadcrumbPaths)
}

/// Renders an `AuditReport` as human-readable text, grouped into three
/// possible sections by the `transitive` classification. Sections with no
/// entries are omitted. Returns a fixed "No deprecated products found." line
/// when the report is empty.
func renderAuditReportAsText(_ report: AuditReport) -> String {
    guard !report.deprecated.products.isEmpty else {
        return "No deprecated products found."
    }

    var sectionsOutput: [String] = []
    let sections: [(header: String, kind: DeprecatedProduct.Transitive)] = [
        ("Directly consumed deprecated products:", .direct),
        ("Transitively reachable deprecated products:", .transitiveReachable),
        ("Transitively unreachable deprecated products:", .transitiveUnreachable),
    ]
    for section in sections {
        let entries = report.deprecated.products.filter { $0.transitive == section.kind }
        guard !entries.isEmpty else { continue }
        sectionsOutput.append(renderSection(header: section.header, entries: entries))
    }
    return sectionsOutput.joined(separator: "\n\n")
}

/// Formats a single audit section: header line followed by per-package
/// groupings, each with one indented block per deprecated product.
private func renderSection(header: String, entries: [DeprecatedProduct]) -> String {
    var lines: [String] = [header]
    var currentPackage: String? = nil
    for entry in entries {
        if entry.package != currentPackage {
            lines.append("  package '\(entry.package)':")
            currentPackage = entry.package
        }
        lines.append("    \(entry.type) '\(entry.product)' is unsupported")
        if let message = entry.message, !message.isEmpty {
            lines.append("      \(message)")
        }
        if let replacement = entry.replacement {
            lines.append("      \(replacement.formattedInstruction)")
        }
        if !entry.usedBy.isEmpty {
            lines.append("      Used by: \(entry.usedBy.joined(separator: ", "))")
        }
    }
    return lines.joined(separator: "\n")
}

/// Maps a `ProductType` to the schema-legal string used in the audit JSON
/// output. Returns `nil` for product kinds that cannot be declared as
/// deprecated via the public API (test/snippet/macro), so those are silently
/// filtered out of the report.
func auditProductTypeString(_ type: ProductType) -> String? {
    switch type {
    case .executable:
        return "executable"
    case .library:
        return "library"
    case .plugin:
        return "plugin"
    case .snippet, .test, .macro:
        return nil
    }
}

// MARK: - Report-level helpers

extension AuditReport {
    /// `true` iff any product in the report should fail the audit (any
    /// non-empty report has at least one violation).
    var hasViolations: Bool {
        !self.deprecated.products.isEmpty
    }
}
