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
import PackageAudit
import PackageGraph
import PackageModel
import Workspace

import struct TSCUtility.Version

/// Determines how each finding of an audit report can be fixed.
struct FixClassifier {
    /// Every version, including prereleases. `VersionSetSpecifier.any.difference(_:)` traps,
    /// so exclusions start from this explicit range.
    private static let allVersions = VersionSetSpecifier.range(Self.lowestVersion ..< Version(Int.max, 0, 0))
    private static let lowestVersion = Version(0, 0, 0, prereleaseIdentifiers: ["0"])

    private let workspace: Workspace
    private let root: PackageGraphRootInput
    private let graph: ModulesGraph
    private let observabilityScope: ObservabilityScope

    init(
        workspace: Workspace,
        root: PackageGraphRootInput,
        graph: ModulesGraph,
        observabilityScope: ObservabilityScope
    ) {
        self.workspace = workspace
        self.root = root
        self.graph = graph
        self.observabilityScope = observabilityScope
    }

    /// Returns `report` with `fixClassification` set on every non-ignored finding.
    ///
    /// Findings of the same package share one dry-run resolution that excludes all of their vulnerable versions.
    /// Dry runs are performed one after another since `Workspace.resolveDryRun` is not safe to call concurrently.
    func classify(_ report: AuditReport) async throws -> AuditReport {
        var result = report
        var indicesByPackage: [PackageIdentity: [Int]] = [:]
        var order: [PackageIdentity] = []
        for (index, finding) in report.findings.enumerated() where !finding.ignored {
            if indicesByPackage[finding.package.identity] == nil {
                order.append(finding.package.identity)
            }
            indicesByPackage[finding.package.identity, default: []].append(index)
        }

        let pins = try self.workspace.resolvedPackagesStore.load().resolvedPackages
        for identity in order {
            let indices = indicesByPackage[identity] ?? []

            // Only findings with a patched version need the resolver.
            var fixable: [Int] = []
            for index in indices {
                if report.findings[index].fixedVersions.isEmpty {
                    result.findings[index].fixClassification = FixClassification.none
                } else {
                    fixable.append(index)
                }
            }
            guard !fixable.isEmpty else { continue }

            let findings = fixable.map { report.findings[$0] }
            let classification: FixClassification
            if let reference = pins[identity]?.packageRef,
               try await self.updateResolves(reference, findings: findings) {
                classification = .update
            } else {
                classification = self.requirementClassification(
                    of: identity,
                    fixedVersions: findings.map(\.fixedVersions)
                )
            }
            for index in fixable {
                result.findings[index].fixClassification = classification
            }
        }
        return result
    }

    /// A constraint that allows any version of `package` outside the vulnerable ranges of `findings`
    /// and other than their pinned version. All `findings` must be of the same package.
    static func excludingConstraint(for package: PackageReference, findings: [AuditFinding]) -> PackageContainerConstraint {
        var vulnerable: [Range<Version>] = []
        for finding in findings {
            let ranges = self.vulnerableRanges(of: finding)
            if ranges.isEmpty, let lowestFixed = finding.fixedVersions.min() {
                // Without ranges, only versions from the lowest fix on are known not to be vulnerable.
                vulnerable.append(Self.lowestVersion ..< lowestFixed)
            } else {
                vulnerable += ranges
            }
        }
        // `difference` expects sorted, disjoint ranges, which `union(from:)` produces.
        var allowed = Self.allVersions.difference(.union(from: vulnerable))
        // The pinned version is vulnerable even if no range covers it (e.g. it is only listed explicitly).
        if case .version(let pinned)? = findings.first?.package.state {
            allowed = allowed.difference(.exact(pinned))
        }
        return PackageContainerConstraint(package: package, requirement: .versionSet(allowed), products: .nothing)
    }

    /// The vulnerable ranges of a finding's advisory that apply to its package.
    ///
    /// Database records are matched by the package's normalized repository URLs. Registry records are scoped to
    /// the package and need not name it, so when none of their entries match by name all entries are used.
    private static func vulnerableRanges(of finding: AuditFinding) -> [Range<Version>] {
        let urls: [String]
        switch finding.package.kind {
        case .sourceControl(let url):
            urls = [url]
        case .registry:
            urls = finding.package.repositoryURLs
        case .local:
            urls = []
        }
        let ranges = urls.compactMap(SwiftURLName.normalize).flatMap {
            finding.advisory.vulnerableRanges(packageName: $0)
        }
        if ranges.isEmpty, case .registry = finding.package.kind {
            return finding.advisory.vulnerableRanges(packageName: nil)
        }
        return ranges
    }

    /// Whether unpinning the package and resolving without its vulnerable versions succeeds.
    private func updateResolves(_ package: PackageReference, findings: [AuditFinding]) async throws -> Bool {
        let result = try await self.workspace.resolveDryRun(
            root: self.root,
            unpinning: [package.identity],
            extraConstraints: [Self.excludingConstraint(for: package, findings: findings)],
            observabilityScope: self.observabilityScope.makeChildScope(
                description: "Classifying fix for \(package.identity)"
            )
        )
        if case .success = result {
            return true
        }
        return false
    }

    /// Classifies a package that cannot be fixed by an update alone, from the requirements declared on it.
    ///
    /// `fixedVersions` holds the patched versions of each fixable finding. A version requirement blocks the fix
    /// if it contains none of the patched versions of at least one finding.
    private func requirementClassification(
        of identity: PackageIdentity,
        fixedVersions: [[Version]]
    ) -> FixClassification {
        func blocks(_ set: VersionSetSpecifier) -> Bool {
            fixedVersions.contains { fixes in !fixes.contains(where: { set.contains($0) }) }
        }

        let parents = self.graph.packages.filter { $0.dependencies.contains(identity) }

        var blockingRoots: [String] = []
        for parent in parents where self.graph.isRootPackage(parent) {
            guard let requirement = Self.requirement(of: parent, on: identity) else { continue }
            switch requirement {
            case .versions(let set):
                if blocks(set) {
                    return .manifest
                }
            case .other:
                // A branch or revision requirement is not fixed by changing a version requirement.
                blockingRoots.append(parent.manifest.displayName)
            }
        }
        if !blockingRoots.isEmpty {
            return .upstream(blockedBy: Self.sortedUnique(blockingRoots))
        }

        let intermediates = parents.filter { !self.graph.isRootPackage($0) }
        let blocking = intermediates.filter { parent in
            switch Self.requirement(of: parent, on: identity) {
            case .versions(let set):
                return blocks(set)
            case .other:
                return true
            case nil:
                return false
            }
        }
        let blockedBy = (blocking.isEmpty ? intermediates : blocking).map(\.manifest.displayName)
        return .upstream(blockedBy: Self.sortedUnique(blockedBy))
    }

    private enum DeclaredRequirement {
        case versions(VersionSetSpecifier)
        case other
    }

    /// The requirement `package` declares on the dependency `identity`, if any.
    private static func requirement(of package: ResolvedPackage, on identity: PackageIdentity) -> DeclaredRequirement? {
        guard let dependency = package.manifest.dependencies.first(where: { $0.identity == identity }) else {
            return nil
        }
        switch dependency {
        case .sourceControl(let settings):
            switch settings.requirement {
            case .exact(let version):
                return .versions(.exact(version))
            case .range(let range):
                return .versions(.range(range))
            case .branch, .revision:
                return .other
            }
        case .registry(let settings):
            switch settings.requirement {
            case .exact(let version):
                return .versions(.exact(version))
            case .range(let range):
                return .versions(.range(range))
            }
        case .fileSystem:
            return .other
        }
    }

    private static func sortedUnique(_ names: [String]) -> [String] {
        Array(Set(names)).sorted()
    }
}
