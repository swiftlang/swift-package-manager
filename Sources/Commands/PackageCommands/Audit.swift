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

    @Flag(
        name: .customLong("include-transitive"),
        help: "Report deprecated products reachable through the graph even when no local target consumes them.",
    )
    var includeTransitive: Bool = false

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
            includeTransitive: self.includeTransitive,
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

        if !report.deprecated.products.isEmpty && !self.allowDeprecations {
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

// MARK: - Report model (internal so unit tests can construct + assert)

struct AuditReport: Codable, Equatable {
    struct Deprecated: Codable, Equatable {
        var products: [DeprecatedProduct]
    }

    var deprecated: Deprecated
}

struct DeprecatedProduct: Codable, Equatable {
    var message: String?
    var package: String
    var product: String
    var replacement: ProductDeprecation.Replacement?
    var type: String
    var usedBy: [String]
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
///   - includeTransitive: When `true`, also reports deprecated products
///     reachable via the graph that are not consumed by any root-package
///     target (they appear with an empty `usedBy` list). When `false`, such
///     products are omitted.
/// - Returns: An `AuditReport` with products sorted by `(package, product)`
///   for deterministic output.
func buildAuditReport(
    graph: ModulesGraph,
    includeTransitive: Bool,
) -> AuditReport {
    // Consumer map: which root-package targets consume each product?
    // Keyed by (packageIdentity, productName) — same product name in
    // different packages is considered distinct.
    var usedBy: [ProductKey: [String]] = [:]
    for rootPackage in graph.rootPackages {
        for module in rootPackage.modules {
            for dependency in module.dependencies {
                guard let product = dependency.product else { continue }
                let key = ProductKey(
                    package: product.packageIdentity.description,
                    product: product.name,
                )
                usedBy[key, default: []].append(module.name)
            }
        }
    }

    var entries: [DeprecatedProduct] = []
    for product in graph.allProducts {
        guard let deprecation = product.underlying.deprecation else { continue }
        guard let typeString = auditProductTypeString(product.type) else { continue }

        let key = ProductKey(
            package: product.packageIdentity.description,
            product: product.name,
        )
        let usedByForProduct = (usedBy[key] ?? []).sorted()

        if usedByForProduct.isEmpty && !includeTransitive {
            continue
        }

        entries.append(
            DeprecatedProduct(
                message: deprecation.message,
                package: product.packageIdentity.description,
                product: product.name,
                replacement: deprecation.replacement,
                type: typeString,
                usedBy: usedByForProduct,
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

/// Renders an `AuditReport` as human-readable text, grouped by producing
/// package. Returns a fixed "No deprecated products found." line when the
/// report is empty.
func renderAuditReportAsText(_ report: AuditReport) -> String {
    guard !report.deprecated.products.isEmpty else {
        return "No deprecated products found."
    }
    var lines: [String] = []
    var currentPackage: String? = nil
    for entry in report.deprecated.products {
        if entry.package != currentPackage {
            if currentPackage != nil {
                lines.append("")
            }
            lines.append("package '\(entry.package)':")
            currentPackage = entry.package
        }
        lines.append("  \(entry.type) '\(entry.product)' is unsupported")
        if let message = entry.message, !message.isEmpty {
            lines.append("    \(message)")
        }
        if let replacement = entry.replacement {
            lines.append("    \(replacement.formattedInstruction)")
        }
        if !entry.usedBy.isEmpty {
            lines.append("    Used by: \(entry.usedBy.joined(separator: ", "))")
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
