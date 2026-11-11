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

public enum FixClassification: Sendable, Equatable {
    case update
    case manifest
    case upstream(blockedBy: [String])
    case none
}

public struct AuditFinding: Sendable {
    public let package: AuditedPackage
    public let advisory: OSVRecord
    public let severity: AdvisorySeverity
    /// The advisory sources that reported this finding.
    public let sources: [String]
    public let fixedVersions: [Version]
    public let ignored: Bool
    public var fixClassification: FixClassification?

    public init(
        package: AuditedPackage,
        advisory: OSVRecord,
        severity: AdvisorySeverity,
        sources: [String],
        fixedVersions: [Version],
        ignored: Bool,
        fixClassification: FixClassification? = nil
    ) {
        self.package = package
        self.advisory = advisory
        self.severity = severity
        self.sources = sources
        self.fixedVersions = fixedVersions
        self.ignored = ignored
        self.fixClassification = fixClassification
    }
}

/// A package that no advisory source could check.
public struct UncheckedPackage: Sendable {
    public let package: AuditedPackage
    public let reason: String

    public init(package: AuditedPackage, reason: String) {
        self.package = package
        self.reason = reason
    }
}

public struct AuditReport: Sendable {
    public let scannedPackages: Int
    public var findings: [AuditFinding]
    public let unchecked: [UncheckedPackage]

    public init(scannedPackages: Int, findings: [AuditFinding], unchecked: [UncheckedPackage]) {
        self.scannedPackages = scannedPackages
        self.findings = findings
        self.unchecked = unchecked
    }

    /// 2 when a non-ignored finding meets `threshold`, or when `failOnUnchecked` is set and
    /// some package could not be checked; 0 otherwise. Operational failures are thrown, not reported here.
    public func exitStatus(threshold: AdvisorySeverity, failOnUnchecked: Bool) -> Int32 {
        if self.findings.contains(where: { !$0.ignored && $0.severity.meets(threshold) }) {
            return 2
        }
        if failOnUnchecked && !self.unchecked.isEmpty {
            return 2
        }
        return 0
    }
}

/// Audits packages against an OSV database and/or a registry and merges the results.
public struct PackageAuditor {
    private static let maxConcurrentRegistryRequests = 8

    private let database: (any AdvisoryDatabase)?
    private let registry: (any RegistryAdvisoryProvider)?
    private let ignoredIDs: Set<String>

    public init(
        database: (any AdvisoryDatabase)?,
        registry: (any RegistryAdvisoryProvider)?,
        ignoredIDs: Set<String>
    ) {
        self.database = database
        self.registry = registry
        self.ignoredIDs = ignoredIDs
    }

    /// An advisory record with the source it came from and the package name used to match its ranges.
    private struct Hit {
        let record: OSVRecord
        let source: String
        let packageName: String?
    }

    public func audit(_ packages: [AuditedPackage]) async throws -> AuditReport {
        // Plan the database queries of every package up front so they go out as one batch.
        var plans: [[AdvisoryQuery]] = []
        var unsupportedReason: [Int: String] = [:]
        for (index, package) in packages.enumerated() {
            let (queries, reason) = self.databaseQueries(for: package)
            plans.append(queries)
            if let reason { unsupportedReason[index] = reason }
        }

        var databaseResults: [AdvisoryQuery: [OSVRecord]] = [:]
        let allQueries = Set(plans.joined()).sorted {
            ($0.name, $0.version?.description ?? "", $0.commit ?? "")
                < ($1.name, $1.version?.description ?? "", $1.commit ?? "")
        }
        if let database = self.database, !allQueries.isEmpty {
            databaseResults = try await database.advisories(for: allQueries)
        }

        let registryResults = try await self.registryAdvisories(for: packages)

        var findings: [AuditFinding] = []
        var unchecked: [UncheckedPackage] = []

        for (index, package) in packages.enumerated() {
            var databaseHits: [Hit] = []
            var registryHits: [Hit] = []
            var checked = false

            if let database = self.database {
                for query in plans[index] {
                    guard let records = databaseResults[query] else { continue }
                    checked = true
                    databaseHits += records.filter { Self.isRelevant($0, query: query, package: package) }.map { Hit(record: $0, source: database.displayName, packageName: query.name) }
                }
            }

            if let records = registryResults[index] {
                checked = true
                let source = Self.registrySourceName(of: package)
                registryHits += records.filter { Self.isRelevant($0, query: nil, package: package) }.map { Hit(record: $0, source: source, packageName: nil) }
            }

            guard checked else {
                unchecked.append(UncheckedPackage(
                    package: package,
                    reason: self.uncheckedReason(for: package, databaseReason: unsupportedReason[index])
                ))
                continue
            }
            // Registry hits first so that the registry record takes precedence.
            findings += self.merge(registryHits + databaseHits, for: package)
        }

        findings.sort {
            ($0.package.identity.description, $0.advisory.id) < ($1.package.identity.description, $1.advisory.id)
        }
        return AuditReport(scannedPackages: packages.count, findings: findings, unchecked: unchecked)
    }

    // MARK: - Planning

    /// The database queries for a package, plus the reason none could be made (if empty).
    private func databaseQueries(for package: AuditedPackage) -> ([AdvisoryQuery], String?) {
        guard let database = self.database else { return ([], "advisory database disabled") }

        let urls: [String]
        switch package.kind {
        case .local:
            return ([], "local dependency")
        case .sourceControl(let url):
            urls = [url]
        case .registry:
            urls = package.repositoryURLs
        }

        let names = urls.compactMap(SwiftURLName.normalize)
        guard !names.isEmpty else {
            return ([], "no repository URL known for the advisory database")
        }

        switch package.state {
        case .version(let version):
            return (names.map { AdvisoryQuery(name: $0, version: version) }, nil)
        case .revision(let commit):
            guard database.supportsCommitQueries else {
                return ([], "\(database.displayName) cannot be queried by commit and the dependency is pinned to a revision")
            }
            return (names.map { AdvisoryQuery(name: $0, commit: commit) }, nil)
        case .none:
            return ([], "dependency is not pinned to a version or revision")
        }
    }

    private func uncheckedReason(for package: AuditedPackage, databaseReason: String?) -> String {
        if case .local = package.kind { return "local dependency" }
        switch package.kind {
        case .registry where self.registry != nil:
            return [
                "registry does not provide advisories",
                databaseReason,
            ].compactMap { $0 }.joined(separator: "; ")
        default:
            return databaseReason ?? "no advisory source available"
        }
    }

    /// Sources may return records that do not apply to the pinned version, so the client
    /// evaluates the ranges itself. Commit queries are answered by the database and kept as is.
    private static func isRelevant(_ record: OSVRecord, query: AdvisoryQuery?, package: AuditedPackage) -> Bool {
        if let query, query.commit != nil { return true }
        guard case .version(let pinned) = package.state else { return true }
        return record.affects(pinned, packageName: query?.name)
    }

    private static func registrySourceName(of package: AuditedPackage) -> String {
        if case .registry(_, let url) = package.kind, let url { return url.absoluteString }
        return "registry"
    }

    // MARK: - Registry

    /// Advisories per package index for registry packages whose registry supports advisories.
    private func registryAdvisories(for packages: [AuditedPackage]) async throws -> [Int: [OSVRecord]] {
        guard let registry = self.registry else { return [:] }

        var work: [(Int, PackageIdentity, Version)] = []
        for (index, package) in packages.enumerated() {
            if case .registry(let identity, _) = package.kind, case .version(let version) = package.state {
                work.append((index, identity, version))
            }
        }

        var results: [Int: [OSVRecord]] = [:]
        try await withThrowingTaskGroup(of: (Int, [OSVRecord]?).self) { group in
            var iterator = work.makeIterator()
            func addNext() -> Bool {
                guard let (index, identity, version) = iterator.next() else { return false }
                group.addTask {
                    do {
                        return (index, try await registry.advisories(for: identity, version: version))
                    } catch let error as AuditError {
                        throw error
                    } catch {
                        throw AuditError.advisorySourceFailed(
                            source: "registry",
                            package: identity.description,
                            underlying: "\(error)"
                        )
                    }
                }
                return true
            }
            for _ in 0 ..< Self.maxConcurrentRegistryRequests where addNext() {}
            while let (index, records) = try await group.next() {
                if let records { results[index] = records }
                _ = addNext()
            }
        }
        return results
    }

    // MARK: - Merging

    private func merge(_ hits: [Hit], for package: AuditedPackage) -> [AuditFinding] {
        struct Group {
            var primary: Hit
            var members: [Hit]
            var ids: Set<String>
        }

        var groups: [Group] = []
        for hit in hits where hit.record.withdrawn == nil {
            // Grouping by any shared identifier (id or alias) is intentional: it is broader than
            // the strict rule so records that only meet through a third record still collapse.
            let ids = Set([hit.record.id] + (hit.record.aliases ?? []))
            let overlapping = groups.indices.filter { !groups[$0].ids.isDisjoint(with: ids) }
            if let first = overlapping.first {
                // A hit may bridge several groups; merge them all into the earliest one,
                // whose primary (a registry record when present) is kept.
                for index in overlapping.dropFirst().reversed() {
                    groups[first].members += groups[index].members
                    groups[first].ids.formUnion(groups[index].ids)
                    groups.remove(at: index)
                }
                groups[first].members.append(hit)
                groups[first].ids.formUnion(ids)
            } else {
                groups.append(Group(primary: hit, members: [hit], ids: ids))
            }
        }

        return groups.map { group in
            var sources: [String] = []
            for member in group.members where !sources.contains(member.source) {
                sources.append(member.source)
            }

            var fixed = Set<Version>()
            if case .version(let pinned) = package.state {
                for member in group.members {
                    fixed.formUnion(member.record.fixedVersions(after: pinned, packageName: member.packageName))
                }
            }

            return AuditFinding(
                package: package,
                advisory: group.primary.record,
                severity: AdvisorySeverity(record: group.primary.record),
                sources: sources,
                fixedVersions: fixed.sorted(),
                ignored: !self.ignoredIDs.isDisjoint(with: group.ids),
                fixClassification: nil
            )
        }
    }
}
