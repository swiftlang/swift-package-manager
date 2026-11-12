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
import PackageAudit
import PackageModel
import Testing
import Workspace
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

@testable
import Commands

import struct TSCUtility.Version

struct FixClassifierTests {
    private let sandbox = AbsolutePath("/tmp/ws/")

    // MARK: - Classifications

    @Test
    func updateWhenAPatchedVersionIsWithinAllRequirements() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0", "1.0.1"])],
            pins: ["Foo"]
        )

        let report = try await fixture.classify(["foo": [Self.advisory(id: "A-1", fixed: "1.0.1")]])

        #expect(report.findings.map(\.fixClassification) == [.update])
        // A dry run never changes the pins.
        #expect(try fixture.pinnedVersion("foo") == "1.0.0")
    }

    @Test
    func manifestWhenTheRootRequirementExcludesEveryPatchedVersion() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMinor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0", "1.1.0"])],
            pins: ["Foo"]
        )

        let report = try await fixture.classify(["foo": [Self.advisory(id: "A-1", fixed: "1.1.0")]])

        #expect(report.findings.map(\.fixClassification) == [.manifest])
    }

    @Test
    func upstreamNamesTheIntermediateDependencyThatExcludesThePatch() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./PatternMatcher", requirement: .upToNextMajor(from: "1.0.0"))],
            packages: [
                try MockPackage(
                    name: "PatternMatcher",
                    targets: [MockTarget(name: "PatternMatcher", dependencies: ["RegEx"])],
                    products: [MockProduct(name: "PatternMatcher", modules: ["PatternMatcher"])],
                    dependencies: [.sourceControl(path: "./RegEx", requirement: .upToNextMajor(from: "1.0.0"))],
                    versions: ["1.0.0"]
                ),
                Self.leaf("RegEx", versions: ["1.0.0", "2.0.0"]),
            ],
            pins: ["PatternMatcher", "RegEx"]
        )

        let report = try await fixture.classify(["regex": [Self.advisory(id: "A-1", fixed: "2.0.0")]])

        #expect(report.findings.map(\.fixClassification) == [.upstream(blockedBy: ["PatternMatcher"])])
    }

    @Test
    func noneWithoutPatchedVersionAndIgnoredFindingsStayUnclassified() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0", "1.0.1"])],
            pins: ["Foo"]
        )

        let report = try await fixture.classify(
            ["foo": [Self.advisory(id: "A-1", fixed: nil), Self.advisory(id: "A-2", fixed: "1.0.1")]],
            ignoredIDs: ["A-2"]
        )

        #expect(report.findings.map(\.advisory.id) == ["A-1", "A-2"])
        #expect(report.findings.map(\.fixClassification) == [FixClassification.none, nil])
    }

    @Test
    func manifestWhenTheRootRequirementExcludesEveryPatchOfOneFinding() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0", "1.0.1", "2.0.0"])],
            pins: ["Foo"]
        )

        // A is fixed within 1.x, but B only in 2.0.0, which the root requirement excludes.
        let report = try await fixture.classify(
            ["foo": [Self.advisory(id: "A-1", fixed: "1.0.1"), Self.advisory(id: "A-2", fixed: "2.0.0")]]
        )

        #expect(report.findings.map(\.fixClassification) == [.manifest, .manifest])
    }

    @Test
    func upstreamWithoutBlockerWhenNoRequirementExcludesThePatch() async throws {
        // The advisory names 1.0.1 as fixed, but that version is not tagged.
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0"])],
            pins: ["Foo"]
        )

        let report = try await fixture.classify(["foo": [Self.advisory(id: "A-1", fixed: "1.0.1")]])

        #expect(report.findings.map(\.fixClassification) == [.upstream(blockedBy: [])])
    }

    // MARK: - Exclusion constraint

    @Test
    func excludingConstraintRemovesTheUnionOfVulnerableRangesAndThePin() throws {
        let package = AuditedPackage(
            identity: "foo",
            kind: .sourceControl(url: "https://example.com/org/foo.git"),
            state: .version("1.0.0")
        )
        let name = "example.com/org/foo"
        let findings = [
            Self.finding(package, Self.advisory(id: "A-1", name: name, ranges: [("1.0.0", "1.0.2"), ("1.0.1", "1.1.0")])),
            Self.finding(package, Self.advisory(id: "A-2", name: name, ranges: [("1.1.0", "1.2.0"), ("2.0.0", "2.1.0")])),
            // Ranges for other packages in the same record are not excluded.
            Self.finding(package, OSVRecord(id: "A-3", affected: [
                Self.advisory(id: "A-3", name: name, ranges: [("1.0.0", "1.0.2")]).affected![0],
                Self.advisory(id: "A-3", name: "example.com/org/other", ranges: [("3.0.0", "4.0.0")]).affected![0],
            ])),
        ]
        let reference = PackageReference.remoteSourceControl(
            identity: "foo",
            url: SourceControlURL("https://example.com/org/foo.git")
        )

        let constraint = FixClassifier.excludingConstraint(for: reference, findings: findings)

        #expect(constraint.package == reference)
        #expect(constraint.products == .nothing)
        guard case .versionSet(let set) = constraint.requirement else {
            Issue.record("expected a version set, got \(constraint.requirement)")
            return
        }
        for allowed in ["0.9.0", "1.2.0", "1.9.9", "2.1.0", "3.5.0", "100.0.0"] {
            #expect(set.contains(Version(stringLiteral: allowed)), "\(allowed) should be allowed")
        }
        for excluded in ["1.0.0", "1.0.1", "1.0.5", "1.1.3", "2.0.0", "2.0.9"] {
            #expect(!set.contains(Version(stringLiteral: excluded)), "\(excluded) should be excluded")
        }
    }

    @Test
    func excludingConstraintUsesEveryEntryOfRegistryRecords() throws {
        let package = AuditedPackage(
            identity: "acme.foo",
            kind: .registry(identity: "acme.foo", registryURL: nil),
            state: .version("1.0.0")
        )
        // Registry records are scoped to the package and need not name it.
        let record = OSVRecord(
            id: "A-1",
            affected: [.init(ranges: [.init(type: "SEMVER", events: [.init(introduced: "0"), .init(fixed: "1.5.0")])])]
        )
        let reference = PackageReference.registry(identity: "acme.foo")

        let constraint = FixClassifier.excludingConstraint(for: reference, findings: [Self.finding(package, record)])

        guard case .versionSet(let set) = constraint.requirement else {
            Issue.record("expected a version set, got \(constraint.requirement)")
            return
        }
        #expect(!set.contains("1.4.0"))
        #expect(set.contains("1.5.0"))
    }

    @Test
    func excludingConstraintExcludesVersionsBelowTheFixWhenNoRangeApplies() throws {
        let package = AuditedPackage(
            identity: "foo",
            kind: .sourceControl(url: "https://example.com/org/foo.git"),
            state: .version("1.0.0")
        )
        // The record only lists affected versions explicitly; the fix comes from elsewhere.
        let record = OSVRecord(id: "A-1", affected: [
            .init(package: .init(ecosystem: "SwiftURL", name: "example.com/org/foo"), versions: ["1.0.0"]),
        ])
        let finding = AuditFinding(
            package: package,
            advisory: record,
            severity: .low,
            sources: ["test"],
            fixedVersions: ["1.5.0", "2.0.0"],
            ignored: false
        )
        let reference = PackageReference.remoteSourceControl(
            identity: "foo",
            url: SourceControlURL("https://example.com/org/foo.git")
        )

        let constraint = FixClassifier.excludingConstraint(for: reference, findings: [finding])

        guard case .versionSet(let set) = constraint.requirement else {
            Issue.record("expected a version set, got \(constraint.requirement)")
            return
        }
        for excluded in ["0.1.0", "1.0.0", "1.2.0", "1.4.9"] {
            #expect(!set.contains(Version(stringLiteral: excluded)), "\(excluded) should be excluded")
        }
        for allowed in ["1.5.0", "1.6.0", "2.0.0"] {
            #expect(set.contains(Version(stringLiteral: allowed)), "\(allowed) should be allowed")
        }
    }

    // MARK: - Fixtures

    private struct Fixture {
        let workspace: MockWorkspace
        let graph: ModulesGraph

        func pinnedVersion(_ identity: String) throws -> Version? {
            let pin = try workspace.getOrCreateWorkspace().resolvedPackagesStore.load()
                .resolvedPackages[PackageIdentity.plain(identity)]
            guard case .version(let version, _)? = pin?.state else { return nil }
            return version
        }

        /// Audits the graph against `advisories` (keyed by identity) and classifies the result.
        func classify(_ advisories: [String: [OSVRecord]], ignoredIDs: Set<String> = []) async throws -> AuditReport {
            let ws = try workspace.getOrCreateWorkspace()
            let packages = AuditInputBuilder.makePackages(graph: graph, resolvedPackages: try ws.resolvedPackagesStore.load())

            var findings: [AuditFinding] = []
            for package in packages {
                for record in advisories[package.identity.description] ?? [] {
                    // Re-target the record at the package's normalized URL, as an OSV database would.
                    guard case .sourceControl(let url) = package.kind, let name = SwiftURLName.normalize(url) else {
                        Issue.record("unexpected package kind \(package.kind)")
                        continue
                    }
                    var named = record
                    named.affected = record.affected?.map { entry in
                        var entry = entry
                        entry.package = .init(ecosystem: "SwiftURL", name: name)
                        return entry
                    }
                    findings.append(FixClassifierTests.finding(package, named, ignored: ignoredIDs.contains(record.id)))
                }
            }
            let report = AuditReport(scannedPackages: packages.count, findings: findings, unchecked: [])

            let observability = ObservabilitySystem.makeForTesting()
            let root = try PackageGraphRootInput(
                packages: workspace.rootPaths(for: ["Root"]),
                traitConfiguration: workspace.traitConfiguration
            )
            let classified = try await FixClassifier(
                workspace: ws,
                root: root,
                graph: graph,
                observabilityScope: observability.topScope
            ).classify(report)
            #expect(!observability.diagnostics.contains { $0.severity == .error }, "\(observability.diagnostics)")
            return classified
        }
    }

    /// Creates a workspace with a single `Root` package, pins each package in `pins` at 1.0.0,
    /// and loads the graph without the pinning constraints.
    private func makeFixture(
        rootDependencies: [MockDependency],
        packages: [MockPackage],
        pins: [String]
    ) async throws -> Fixture {
        let fs = InMemoryFileSystem()
        // Each root dependency vends a product named like its directory.
        let rootTargetDependencies: [TargetDescription.Dependency] = pins.prefix(rootDependencies.count).map {
            .byName(name: $0, condition: nil)
        }
        let workspace = try await MockWorkspace(
            sandbox: self.sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Root",
                    targets: [MockTarget(name: "Root", dependencies: rootTargetDependencies)],
                    products: [MockProduct(name: "Root", modules: ["Root"])],
                    dependencies: rootDependencies
                ),
            ],
            packages: packages
        )

        let pinningDependencies: [MockDependency] = pins.map {
            .sourceControl(path: "./\($0)", requirement: .exact("1.0.0"), products: .specific([$0]))
        }
        try await workspace.checkPackageGraph(roots: ["Root"], deps: pinningDependencies) { _, diagnostics in
            #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
        }

        var loaded: ModulesGraph?
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
            loaded = graph
        }
        return Fixture(workspace: workspace, graph: try #require(loaded))
    }

    private static func leaf(_ name: String, versions: [String]) -> MockPackage {
        try! MockPackage(
            name: name,
            targets: [MockTarget(name: name)],
            products: [MockProduct(name: name, modules: [name])],
            versions: versions
        )
    }

    /// A record affecting every version before `fixed` (or every version when `fixed` is nil).
    private static func advisory(id: String, fixed: String?) -> OSVRecord {
        var events: [OSVRecord.Event] = [.init(introduced: "0")]
        if let fixed { events.append(.init(fixed: fixed)) }
        return OSVRecord(id: id, affected: [.init(ranges: [.init(type: "SEMVER", events: events)])])
    }

    private static func advisory(id: String, name: String, ranges: [(String, String)]) -> OSVRecord {
        OSVRecord(id: id, affected: [
            .init(
                package: .init(ecosystem: "SwiftURL", name: name),
                ranges: ranges.map { .init(type: "SEMVER", events: [.init(introduced: $0.0), .init(fixed: $0.1)]) }
            ),
        ])
    }

    fileprivate static func finding(_ package: AuditedPackage, _ record: OSVRecord, ignored: Bool = false) -> AuditFinding {
        var fixed: [Version] = []
        if case .version(let pinned) = package.state {
            let name: String? = record.affected?.first?.package?.name
            fixed = record.fixedVersions(after: pinned, packageName: name)
        }
        return AuditFinding(
            package: package,
            advisory: record,
            severity: AdvisorySeverity(record: record),
            sources: ["test"],
            fixedVersions: fixed,
            ignored: ignored
        )
    }
}
