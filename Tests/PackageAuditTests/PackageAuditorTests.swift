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
@testable import PackageAudit
import Testing

import struct TSCBasic.StringError

import struct TSCUtility.Version

private struct MockDatabase: AdvisoryDatabase {
    let displayName = "mock-db"
    let supportsCommitQueries: Bool
    /// Records keyed by normalized name; commit queries are keyed by "name@commit".
    let records: [String: [OSVRecord]]
    let recorder: QueryRecorder

    func advisories(for queries: [AdvisoryQuery]) async throws -> [AdvisoryQuery: [OSVRecord]] {
        self.recorder.add(queries)
        var result: [AdvisoryQuery: [OSVRecord]] = [:]
        for query in queries {
            if let commit = query.commit {
                guard self.supportsCommitQueries else { continue }
                result[query] = self.records["\(query.name)@\(commit)"] ?? []
            } else {
                result[query] = self.records[query.name] ?? []
            }
        }
        return result
    }
}

private final class QueryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[AdvisoryQuery]] = []
    func add(_ queries: [AdvisoryQuery]) { self.lock.withLock { self.batches.append(queries) } }
    var all: [[AdvisoryQuery]] { self.lock.withLock { self.batches } }
}

private struct MockRegistry: RegistryAdvisoryProvider {
    let result: [String: [OSVRecord]]?

    func advisories(for identity: PackageIdentity, version: Version) async throws -> [OSVRecord]? {
        self.result?[identity.description] ?? (self.result == nil ? nil : [])
    }
}

private func record(
    _ id: String,
    aliases: [String]? = nil,
    summary: String? = nil,
    severity: String = "HIGH",
    withdrawn: String? = nil,
    fixed: String = "1.0.5"
) -> OSVRecord {
    OSVRecord(
        id: id,
        aliases: aliases,
        summary: summary,
        withdrawn: withdrawn,
        affected: [.init(
            package: .init(ecosystem: "SwiftURL", name: "github.com/mona/NetKit"),
            ranges: [.init(type: "SEMVER", events: [.init(introduced: "0"), .init(fixed: fixed)])]
        )],
        databaseSpecific: .init(severity: severity)
    )
}

private let name = "github.com/mona/NetKit"
private let url = "https://github.com/mona/NetKit.git"
private let v1 = Version(1, 0, 0)

private func sourceControl(_ state: AuditedPackage.State) -> AuditedPackage {
    AuditedPackage(identity: .plain("netkit"), kind: .sourceControl(url: url), state: state)
}

private func registryPackage(repositoryURLs: [String] = [url]) -> AuditedPackage {
    AuditedPackage(
        identity: .plain("mona.NetKit"),
        kind: .registry(identity: .plain("mona.NetKit"), registryURL: URL(string: "https://registry.example.com")),
        state: .version(v1),
        repositoryURLs: repositoryURLs
    )
}

private func auditor(
    records: [String: [OSVRecord]] = [:],
    commits: Bool = true,
    registry: [String: [OSVRecord]]?? = .none,
    ignored: Set<String> = [],
    recorder: QueryRecorder = QueryRecorder()
) -> PackageAuditor {
    PackageAuditor(
        database: MockDatabase(supportsCommitQueries: commits, records: records, recorder: recorder),
        registry: registry.map { MockRegistry(result: $0) },
        ignoredIDs: ignored
    )
}

@Suite
struct PackageAuditorTests {
    @Test func sourceControlVersionQueriesDatabase() async throws {
        let recorder = QueryRecorder()
        let report = try await auditor(records: [name: [record("GHSA-1")]], recorder: recorder)
            .audit([sourceControl(.version(v1))])

        #expect(recorder.all == [[AdvisoryQuery(name: name, version: v1)]])
        #expect(report.scannedPackages == 1)
        #expect(report.findings.map(\.advisory.id) == ["GHSA-1"])
        #expect(report.findings[0].sources == ["mock-db"])
        #expect(report.findings[0].fixedVersions == [Version(1, 0, 5)])
        #expect(report.findings[0].severity == .high)
        #expect(report.unchecked.isEmpty)
    }

    @Test func databaseQueriesAreBatchedOnce() async throws {
        let recorder = QueryRecorder()
        let other = AuditedPackage(
            identity: .plain("other"), kind: .sourceControl(url: "https://github.com/mona/other"), state: .version(v1)
        )
        _ = try await auditor(recorder: recorder).audit([sourceControl(.version(v1)), other])
        #expect(recorder.all.count == 1)
        #expect(recorder.all[0].count == 2)
    }

    @Test func revisionPinUsesCommitQueryWhenSupported() async throws {
        let report = try await auditor(records: ["\(name)@abc": [record("GHSA-1")]])
            .audit([sourceControl(.revision("abc"))])
        #expect(report.findings.map(\.advisory.id) == ["GHSA-1"])
        #expect(report.findings[0].fixedVersions.isEmpty)
        #expect(report.unchecked.isEmpty)
    }

    @Test func revisionPinUncheckedWhenLocalDatabase() async throws {
        let report = try await auditor(commits: false).audit([sourceControl(.revision("abc"))])
        #expect(report.findings.isEmpty)
        #expect(report.unchecked.count == 1)
        #expect(report.unchecked[0].reason.contains("commit"))
    }

    @Test func localPackageUnchecked() async throws {
        let local = AuditedPackage(
            identity: .plain("local"), kind: .local(path: try AbsolutePath(validating: "/tmp/local")), state: .none
        )
        let report = try await auditor().audit([local])
        #expect(report.unchecked.map(\.reason) == ["local dependency"])
    }

    @Test func registryPackageQueriesRegistryAndRepositoryURLs() async throws {
        let report = try await auditor(
            records: [name: [record("GHSA-1", summary: "database"), record("GHSA-2")]],
            registry: ["mona.NetKit": [record("GHSA-1", summary: "registry")]]
        ).audit([registryPackage()])

        #expect(report.findings.map(\.advisory.id) == ["GHSA-1", "GHSA-2"])
        let first = report.findings[0]
        #expect(Set(first.sources) == ["https://registry.example.com", "mock-db"])
        #expect(first.advisory.summary == "registry")
        #expect(report.findings[1].sources == ["mock-db"])
    }

    @Test func aliasDedup() async throws {
        let report = try await auditor(
            records: [name: [record("GHSA-1", aliases: ["CVE-1"])]],
            registry: ["mona.NetKit": [record("CVE-1")]]
        ).audit([registryPackage()])
        #expect(report.findings.map(\.advisory.id) == ["CVE-1"])
        #expect(report.findings[0].sources.count == 2)
    }

    @Test func registryUnsupportedFallsBackToDatabase() async throws {
        let report = try await auditor(records: [name: [record("GHSA-1")]], registry: .some(nil))
            .audit([registryPackage()])
        #expect(report.findings.map(\.advisory.id) == ["GHSA-1"])
        #expect(report.unchecked.isEmpty)
    }

    @Test func registryUnsupportedAndNoRepositoryURLsIsUnchecked() async throws {
        let report = try await auditor(registry: .some(nil)).audit([registryPackage(repositoryURLs: [])])
        #expect(report.findings.isEmpty)
        #expect(report.unchecked.count == 1)
        #expect(report.unchecked[0].reason.contains("registry does not provide advisories"))
        #expect(report.unchecked[0].reason.contains("no repository URL"))
    }

    @Test func registrySupportedAndCleanIsChecked() async throws {
        let report = try await auditor(registry: ["mona.NetKit": []]).audit([registryPackage(repositoryURLs: [])])
        #expect(report.unchecked.isEmpty)
    }

    @Test func ignoredByIDOrAlias() async throws {
        let report = try await auditor(
            records: [name: [record("GHSA-1", aliases: ["CVE-1"], severity: "CRITICAL")]],
            ignored: ["CVE-1"]
        ).audit([sourceControl(.version(v1))])
        #expect(report.findings.map(\.ignored) == [true])
        #expect(report.exitStatus(threshold: .low, failOnUnchecked: false) == 0)
    }

    @Test func withdrawnIgnored() async throws {
        let report = try await auditor(
            records: [name: [record("GHSA-1", withdrawn: "2024-01-01T00:00:00Z")]]
        ).audit([sourceControl(.version(v1))])
        #expect(report.findings.isEmpty)
    }

    @Test func registryRecordNotAffectingPinnedVersionIsDropped() async throws {
        let report = try await auditor(
            registry: ["mona.NetKit": [record("GHSA-1", fixed: "0.9.0")]]
        ).audit([registryPackage(repositoryURLs: [])])
        #expect(report.findings.isEmpty)
        #expect(report.unchecked.isEmpty)
        #expect(report.exitStatus(threshold: .low, failOnUnchecked: true) == 0)
    }

    @Test func databaseRecordNotAffectingPinnedVersionIsDropped() async throws {
        let report = try await auditor(records: [name: [record("GHSA-1", fixed: "0.9.0")]])
            .audit([sourceControl(.version(v1))])
        #expect(report.findings.isEmpty)
        #expect(report.unchecked.isEmpty)
    }

    @Test func bridgingRecordMergesGroupsTransitively() async throws {
        let report = try await auditor(
            records: [name: [record("GHSA-1", aliases: ["CVE-1", "GHSA-2"])]],
            registry: ["mona.NetKit": [record("CVE-1", summary: "registry"), record("GHSA-2")]]
        ).audit([registryPackage()])
        #expect(report.findings.count == 1)
        #expect(report.findings[0].advisory.id == "CVE-1")
        #expect(report.findings[0].advisory.summary == "registry")
        #expect(report.findings[0].sources.count == 2)
    }

    @Test func withdrawnRegistryRecordIgnored() async throws {
        let report = try await auditor(
            registry: ["mona.NetKit": [record("GHSA-1", withdrawn: "2024-01-01T00:00:00Z")]]
        ).audit([registryPackage(repositoryURLs: [])])
        #expect(report.findings.isEmpty)
        #expect(report.unchecked.isEmpty)
    }

    @Test func noDatabaseLeavesSourceControlPackageUnchecked() async throws {
        let report = try await PackageAuditor(database: nil, registry: nil, ignoredIDs: [])
            .audit([sourceControl(.version(v1))])
        #expect(report.findings.isEmpty)
        #expect(report.unchecked.count == 1)
        #expect(!report.unchecked[0].reason.isEmpty)
    }

    @Test func genericProviderErrorIsWrapped() async throws {
        struct Failing: RegistryAdvisoryProvider {
            func advisories(for identity: PackageIdentity, version: Version) async throws -> [OSVRecord]? {
                throw StringError("boom")
            }
        }
        let auditor = PackageAuditor(database: nil, registry: Failing(), ignoredIDs: [])
        do {
            _ = try await auditor.audit([registryPackage(repositoryURLs: [])])
            Issue.record("expected audit to throw")
        } catch let error as AuditError {
            guard case .advisorySourceFailed = error else {
                Issue.record("unexpected error \(error)")
                return
            }
            #expect(error.description.contains("mona.NetKit"))
        }
    }

    @Test func exitStatusRules() throws {
        let package = sourceControl(.version(v1))
        func finding(_ severity: AdvisorySeverity) -> AuditFinding {
            AuditFinding(
                package: package, advisory: OSVRecord(id: "X"), severity: severity,
                sources: [], fixedVersions: [], ignored: false
            )
        }
        let unchecked = UncheckedPackage(package: package, reason: "r")

        let clean = AuditReport(scannedPackages: 1, findings: [], unchecked: [])
        #expect(clean.exitStatus(threshold: .low, failOnUnchecked: true) == 0)

        let moderate = AuditReport(scannedPackages: 1, findings: [finding(.moderate)], unchecked: [])
        #expect(moderate.exitStatus(threshold: .high, failOnUnchecked: false) == 0)
        #expect(moderate.exitStatus(threshold: .low, failOnUnchecked: false) == 2)

        let withUnchecked = AuditReport(scannedPackages: 1, findings: [], unchecked: [unchecked])
        #expect(withUnchecked.exitStatus(threshold: .low, failOnUnchecked: false) == 0)
        #expect(withUnchecked.exitStatus(threshold: .low, failOnUnchecked: true) == 2)

        let unknown = AuditReport(scannedPackages: 1, findings: [finding(.unknown)], unchecked: [])
        #expect(unknown.exitStatus(threshold: .critical, failOnUnchecked: false) == 2)
    }
}
