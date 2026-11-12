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

import struct TSCUtility.Version

/// Renders an `AuditReport` as human-readable text or as JSON.
public enum AuditReportRenderer {
    /// Width of the label column in the text output.
    private static let labelWidth = 10

    // MARK: - Text

    /// Ignored findings are listed only when `verbose` is set; they are never counted in the summary.
    public static func text(_ report: AuditReport, verbose: Bool) -> String {
        let findings = report.findings.filter { verbose || !$0.ignored }
        var out = ""

        for finding in findings {
            out += self.block(for: finding)
            out += "\n"
        }

        let scanned = "\(report.scannedPackages) scanned \(report.scannedPackages == 1 ? "package" : "packages")"
        let counted = report.findings.filter { !$0.ignored }
        if counted.isEmpty {
            out += "No known vulnerabilities found in \(scanned).\n"
        } else {
            var counts: [AdvisorySeverity: Int] = [:]
            for finding in counted {
                counts[finding.severity, default: 0] += 1
            }
            let breakdown = AdvisorySeverity.allCases
                .compactMap { severity in counts[severity].map { "\($0) \(severity.rawValue)" } }
                .joined(separator: ", ")
            let total = Self.count(counted.count, "vulnerability", plural: "vulnerabilities")
            out += "Found \(total) (\(breakdown)) in \(scanned).\n"
        }

        let ignoredCount = report.findings.count - counted.count
        if ignoredCount > 0 {
            out += "\(Self.count(ignoredCount, "ignored advisory", plural: "ignored advisories")) not counted."
            out += verbose ? "\n" : " Run with --verbose to show them.\n"
        }

        if !report.unchecked.isEmpty {
            if verbose {
                out += "\(Self.count(report.unchecked.count, "package")) could not be checked:\n"
                for entry in report.unchecked {
                    out += "  \(Self.location(of: entry.package)): \(entry.reason)\n"
                }
            } else {
                let packages = Self.count(report.unchecked.count, "package")
                out += "\(packages) could not be checked; run with --verbose for details.\n"
            }
        }
        return out
    }

    private static func block(for finding: AuditFinding) -> String {
        let advisory = finding.advisory
        var lines: [(String, String)] = []

        var idLine = advisory.id
        if let aliases = advisory.aliases, !aliases.isEmpty {
            idLine += " (\(aliases.joined(separator: ", ")))"
        }
        if finding.ignored {
            idLine += " [ignored]"
        }
        lines.append((finding.severity.rawValue.capitalized, idLine))
        if let summary = advisory.summary, !summary.isEmpty {
            lines.append(("", summary))
        }

        let package = finding.package
        var packageLine = "\(Self.location(of: package))"
        switch package.state {
        case .version(let version): packageLine += " \(version)"
        case .revision(let revision): packageLine += " @ \(revision)"
        case .none: break
        }
        if case .registry = package.kind {
            packageLine += " (registry)"
        }
        lines.append(("Package", packageLine))

        for path in package.paths {
            lines.append(("Path", path.joined(separator: " > ")))
        }
        if !finding.fixedVersions.isEmpty {
            lines.append(("Fixed in", finding.fixedVersions.map(\.description).joined(separator: ", ")))
        }
        if let fix = Self.fixLine(for: finding) {
            lines.append(("Fix", fix))
        }
        lines.append(("More info", Self.moreInfo(for: advisory)))

        return lines
            .map { label, value in
                label.padding(toLength: self.labelWidth, withPad: " ", startingAt: 0) + value
            }
            .joined(separator: "\n") + "\n"
    }

    private static func fixLine(for finding: AuditFinding) -> String? {
        guard let classification = finding.fixClassification else { return nil }
        switch classification {
        case .update:
            return "Run `swift package audit fix` (within current requirements)"
        case .manifest:
            var line = "Requires changing the requirement in Package.swift"
            if case .version(let pinned) = finding.package.state,
               let lowest = finding.fixedVersions.min(),
               lowest.major > pinned.major
            {
                line += " (major version)"
            }
            return line
        case .upstream(let blockedBy):
            guard !blockedBy.isEmpty else {
                // No specific dependency was found to exclude the patched versions.
                return "No resolution avoids the vulnerable versions within current requirements; try `swift package update`"
            }
            return "Blocked by \(blockedBy.joined(separator: ", "))"
        case .none:
            return "No patched version is available"
        }
    }

    private static func moreInfo(for advisory: OSVRecord) -> String {
        let references = advisory.references ?? []
        if let reference = references.first(where: { $0.type == "ADVISORY" }) ?? references.first {
            return reference.url
        }
        return "https://osv.dev/vulnerability/\(advisory.id)"
    }

    private static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    private static func location(of package: AuditedPackage) -> String {
        switch package.kind {
        case .sourceControl(let url): url
        case .registry(let identity, _): identity.description
        case .local(let path): path.pathString
        }
    }

    // MARK: - JSON

    public static func json(_ report: AuditReport) throws -> String {
        let payload = JSONReport(
            version: 1,
            scannedPackages: report.scannedPackages,
            findings: report.findings.map(JSONFinding.init),
            unchecked: report.unchecked.map {
                JSONUnchecked(package: JSONPackage($0.package), reason: $0.reason)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    private struct JSONReport: Encodable {
        let version: Int
        let scannedPackages: Int
        let findings: [JSONFinding]
        let unchecked: [JSONUnchecked]
    }

    private struct JSONUnchecked: Encodable {
        let package: JSONPackage
        let reason: String
    }

    private struct JSONPackage: Encodable {
        let identity: String
        let location: String
        let kind: String
        let version: String?
        let revision: String?

        init(_ package: AuditedPackage) {
            self.identity = package.identity.description
            self.location = AuditReportRenderer.location(of: package)
            switch package.kind {
            case .sourceControl(let url):
                self.kind = url.hasPrefix("file://") ? "localSourceControl" : "remoteSourceControl"
            case .registry:
                self.kind = "registry"
            case .local:
                self.kind = "fileSystem"
            }
            switch package.state {
            case .version(let version):
                self.version = version.description
                self.revision = nil
            case .revision(let revision):
                self.version = nil
                self.revision = revision
            case .none:
                self.version = nil
                self.revision = nil
            }
        }
    }

    private struct JSONFinding: Encodable {
        let package: JSONPackage
        let advisory: OSVRecord
        let severity: String
        let sources: [String]
        let paths: [[String]]
        let fixClassification: String?
        let blockedBy: [String]?
        let fixedVersions: [String]
        let ignored: Bool

        init(_ finding: AuditFinding) {
            self.package = JSONPackage(finding.package)
            self.advisory = finding.advisory
            self.severity = finding.severity.rawValue
            self.sources = finding.sources
            self.paths = finding.package.paths
            self.fixedVersions = finding.fixedVersions.map(\.description)
            self.ignored = finding.ignored
            switch finding.fixClassification {
            case .update:
                self.fixClassification = "update"
                self.blockedBy = nil
            case .manifest:
                self.fixClassification = "manifest"
                self.blockedBy = nil
            case .upstream(let blockedBy):
                self.fixClassification = "upstream"
                self.blockedBy = blockedBy
            case .none?:
                self.fixClassification = "none"
                self.blockedBy = nil
            case nil:
                self.fixClassification = nil
                self.blockedBy = nil
            }
        }
    }
}
