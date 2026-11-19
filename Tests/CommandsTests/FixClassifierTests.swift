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

import struct TSCBasic.StringError
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
    func bareNameRecordIsEvaluatedAgainstTheUpdatedVersion() async throws {
        // 1.0.1 is still affected by the record, which names the package by its bare repository name.
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMinor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0", "1.0.1", "1.1.0"])],
            pins: ["Foo"]
        )

        let report = try await fixture.classify(["foo": [Self.advisory(id: "A-1", name: "Foo", ranges: [("0", "1.1.0")])]])

        #expect(report.findings.map(\.fixClassification) == [.manifest])
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

    @Test
    func notUpdateWhenUpdatingWouldNotLeaveTheVulnerableRange() async throws {
        // Updating Foo, as `audit fix` does, only reaches 1.0.1, which is still vulnerable. Only a downgrade to
        // 0.9.0 avoids the advisory, which an update never does, so the finding must not be classified as `.update`.
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .range("0.9.0" ..< "2.0.0"))],
            packages: [Self.leaf("Foo", versions: ["0.9.0", "1.0.0", "1.0.1"])],
            pins: ["Foo"]
        )
        let advisory = OSVRecord(id: "A-1", affected: [
            .init(ranges: [.init(type: "SEMVER", events: [.init(introduced: "1.0.0"), .init(fixed: "1.1.0")])]),
        ])

        let report = try await fixture.classify(["foo": [advisory]])

        #expect(report.findings.map(\.fixClassification) == [.upstream(blockedBy: [])])
    }

    // MARK: - Branch and revision pins

    @Test
    func manifestWhenARootDependsOnABranchOfTheVulnerablePackage() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .branch("develop"))],
            packages: [Self.leaf("Foo", versions: ["develop"])],
            pins: ["Foo"],
            pinRequirement: .branch("develop")
        )

        let report = try await fixture.classify(["foo": [Self.advisory(id: "A-1", fixed: "1.0.1")]])

        #expect(report.findings.map(\.package.state) == [.revision(try fixture.pinnedRevision("foo"))])
        #expect(report.findings.map(\.fixedVersions) == [["1.0.1"]])
        #expect(report.findings.map(\.fixClassification) == [.manifest])
    }

    @Test
    func upstreamWhenAnIntermediateDependsOnABranchOfTheVulnerablePackage() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./PatternMatcher", requirement: .branch("develop"))],
            packages: [
                try MockPackage(
                    name: "PatternMatcher",
                    targets: [MockTarget(name: "PatternMatcher", dependencies: ["RegEx"])],
                    products: [MockProduct(name: "PatternMatcher", modules: ["PatternMatcher"])],
                    dependencies: [.sourceControl(path: "./RegEx", requirement: .branch("develop"))],
                    versions: ["develop"]
                ),
                Self.leaf("RegEx", versions: ["develop"]),
            ],
            pins: ["PatternMatcher", "RegEx"],
            pinRequirement: .branch("develop")
        )

        let report = try await fixture.classify(["regex": [Self.advisory(id: "A-1", fixed: "2.0.0")]])

        #expect(report.findings.map(\.fixClassification) == [.upstream(blockedBy: ["PatternMatcher"])])
    }

    // MARK: - Failures

    @Test
    func classificationFailureLeavesFindingsUnclassifiedWithOneWarning() async throws {
        let fixture = try await self.makeFixture(
            rootDependencies: [.sourceControl(path: "./Foo", requirement: .upToNextMajor(from: "1.0.0"))],
            packages: [Self.leaf("Foo", versions: ["1.0.0", "1.0.1"])],
            pins: ["Foo"]
        )

        // A root that cannot be loaded makes every dry run fail, as an unreachable dependency would offline.
        let (report, diagnostics) = try await fixture.classifyReturningDiagnostics(
            ["foo": [Self.advisory(id: "A-1", fixed: "1.0.1"), Self.advisory(id: "A-2", fixed: "1.0.1")]],
            rootPaths: [AbsolutePath("/tmp/ws/roots/Missing")]
        )

        #expect(report.findings.map(\.fixClassification) == [nil, nil])
        #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
        let warnings = diagnostics.filter { $0.severity == .warning }
        #expect(warnings.count == 1, "\(diagnostics)")
        #expect(warnings.first?.message.hasPrefix("could not determine how to fix foo: ") == true, "\(warnings)")
    }

    @Test
    func resolverConflictMeansAnUpdateCannotFix() throws {
        let result: Result<[(PackageReference, Workspace.PackageStateChange)], any Error> =
            .failure(PubGrubDependencyResolver.PubGrubError.unresolvable("foo 1.0.1 is excluded"))
        #expect(try FixClassifier.changes(from: result) == nil)
    }

    @Test
    func otherResolutionFailuresAreNotTreatedAsUnfixable() {
        // e.g. a repository that cannot be fetched while offline
        let result: Result<[(PackageReference, Workspace.PackageStateChange)], any Error> =
            .failure(StringError("failed to fetch https://example.com/foo.git"))
        #expect(throws: (any Error).self) { try FixClassifier.changes(from: result) }
    }

    // MARK: - Fixtures

    private struct Fixture {
        let workspace: MockWorkspace
        let fileSystem: InMemoryFileSystem
        let graph: ModulesGraph

        func pinnedRevision(_ identity: String) throws -> String {
            let pin = try workspace.getOrCreateWorkspace().resolvedPackagesStore.load()
                .resolvedPackages[PackageIdentity.plain(identity)]
            switch pin?.state {
            case .branch(_, let revision)?, .revision(let revision)?:
                return revision
            default:
                throw StringError("\(identity) is not pinned to a revision: \(String(describing: pin?.state))")
            }
        }

        func pinnedVersion(_ identity: String) throws -> Version? {
            let pin = try workspace.getOrCreateWorkspace().resolvedPackagesStore.load()
                .resolvedPackages[PackageIdentity.plain(identity)]
            guard case .version(let version, _)? = pin?.state else { return nil }
            return version
        }

        /// Audits the graph against `advisories` (keyed by identity) and classifies the result.
        func classify(_ advisories: [String: [OSVRecord]], ignoredIDs: Set<String> = []) async throws -> AuditReport {
            let (report, diagnostics) = try await self.classifyReturningDiagnostics(advisories, ignoredIDs: ignoredIDs)
            #expect(!diagnostics.contains { $0.severity == .error || $0.severity == .warning }, "\(diagnostics)")
            return report
        }

        /// Like `classify`, but with a custom root and returning the diagnostics emitted to the command scope.
        func classifyReturningDiagnostics(
            _ advisories: [String: [OSVRecord]],
            ignoredIDs: Set<String> = [],
            rootPaths: [AbsolutePath]? = nil
        ) async throws -> (AuditReport, [Basics.Diagnostic]) {
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
                    // Entries that already name a package are kept, to model records using another name shape.
                    var named = record
                    named.affected = record.affected?.map { entry in
                        var entry = entry
                        if entry.package == nil {
                            entry.package = .init(ecosystem: "SwiftURL", name: name)
                        }
                        return entry
                    }
                    findings.append(FixClassifierTests.finding(package, named, ignored: ignoredIDs.contains(record.id)))
                }
            }
            let report = AuditReport(scannedPackages: packages.count, findings: findings, unchecked: [])

            let observability = ObservabilitySystem.makeForTesting()
            let root = try PackageGraphRootInput(
                packages: rootPaths ?? workspace.rootPaths(for: ["Root"]),
                traitConfiguration: workspace.traitConfiguration
            )
            let classified = try await FixClassifier(
                workspace: ws,
                root: root,
                graph: graph,
                observabilityScope: observability.topScope
            ).classify(report)
            return (classified, observability.diagnostics)
        }
    }

    /// Creates a workspace with a single `Root` package, pins each package in `pins` with `pinRequirement`,
    /// and loads the graph without the pinning constraints.
    private func makeFixture(
        rootDependencies: [MockDependency],
        packages: [MockPackage],
        pins: [String],
        pinRequirement: SourceControlRequirement = .exact("1.0.0")
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
            .sourceControl(path: "./\($0)", requirement: pinRequirement, products: .specific([$0]))
        }
        try await workspace.checkPackageGraph(roots: ["Root"], deps: pinningDependencies) { _, diagnostics in
            #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
        }

        var loaded: ModulesGraph?
        try await workspace.checkPackageGraph(roots: ["Root"]) { graph, diagnostics in
            #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
            loaded = graph
        }
        return Fixture(workspace: workspace, fileSystem: fs, graph: try #require(loaded))
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
        // Computed as `PackageAuditor` does.
        let name: String? = record.affected?.first?.package?.name
        let fixed: [Version]
        if case .version(let pinned) = package.state {
            fixed = record.fixedVersions(after: pinned, packageName: name)
        } else {
            fixed = record.fixedVersions(packageName: name)
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
