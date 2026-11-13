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
    private let workspace: Workspace
    private let root: PackageGraphRootInput
    private let graph: ModulesGraph
    private let observabilityScope: ObservabilityScope

    /// - Parameter observabilityScope: Receives a warning for each package whose fix could not be determined.
    ///   The dry-run resolutions report to a separate observability system, so that their failures (for example
    ///   when offline) do not fail the command.
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

    /// Returns `report` with `fixClassification` set on every non-ignored finding whose fix could be determined.
    ///
    /// Findings of the same package share one dry-run resolution equivalent to `swift package update <package>`.
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
            if case .version = findings[0].package.state {
                var updateFixes = false
                do {
                    if let pin = pins[identity] {
                        updateFixes = try await self.updateFixes(pin.packageRef, findings: findings)
                    }
                } catch let error as ClassificationFailure {
                    // The findings stay unclassified rather than failing the audit.
                    self.observabilityScope.emit(warning: "could not determine how to fix \(identity): \(error.reason)")
                    continue
                }
                classification = updateFixes
                    ? .update
                    : self.requirementClassification(of: identity, fixedVersions: findings.map(\.fixedVersions))
            } else {
                classification = self.unversionedClassification(of: identity)
            }
            for index in fixable {
                result.findings[index].fixClassification = classification
            }
        }
        return result
    }

    private struct ClassificationFailure: Error {
        let reason: String
    }

    /// Whether `swift package update <package>` would move the package to a version that none of `findings`
    /// affects, as `swift package audit fix` updates it that way.
    ///
    /// Throws `ClassificationFailure` when the dry run cannot be performed or reports errors.
    private func updateFixes(_ package: PackageReference, findings: [AuditFinding]) async throws -> Bool {
        let errors = ThreadSafeArrayStore<String>()
        let scope = ObservabilitySystem({ _, diagnostic in
            if diagnostic.severity == .error {
                errors.append(diagnostic.message)
            }
        }).topScope

        let result: Result<[(PackageReference, Workspace.PackageStateChange)], any Error>
        do {
            result = try await self.workspace.resolveDryRun(
                root: self.root,
                unpinning: [package.identity],
                observabilityScope: scope
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ClassificationFailure(reason: errors.get().first ?? error.interpolationDescription)
        }
        if let error = errors.get().first {
            throw ClassificationFailure(reason: error)
        }

        guard let changes = try Self.changes(from: result) else {
            return false
        }
        switch changes.first(where: { $0.0.identity == package.identity })?.1 {
        case .added(let state)?, .updated(let state)?:
            guard case .version(let version) = state.requirement else { return false }
            return !findings.contains { Self.isAffected($0, version: version) }
        case .unchanged?, .removed?, nil:
            // The package stays at its vulnerable pin.
            return false
        }
    }

    /// The package state changes of a dry run, or `nil` when the requirements rule out every resolution.
    ///
    /// Only a resolver conflict means an update cannot fix the package. Any other failure, such as a repository
    /// that cannot be fetched offline, says nothing about it and throws instead.
    static func changes(
        from result: Result<[(PackageReference, Workspace.PackageStateChange)], any Error>
    ) throws -> [(PackageReference, Workspace.PackageStateChange)]? {
        switch result {
        case .success(let changes):
            return changes
        case .failure(is PubGrubDependencyResolver.PubGrubError):
            return nil
        case .failure(let error):
            throw ClassificationFailure(reason: error.interpolationDescription)
        }
    }

    /// Whether the advisory of `finding` affects `version` of its package.
    ///
    /// Registry records are scoped to the package and need not name it, so for registry packages every entry is
    /// considered. Database records may name the package by its bare repository name, which is checked as well.
    private static func isAffected(_ finding: AuditFinding, version: Version) -> Bool {
        switch finding.package.kind {
        case .sourceControl(let url):
            guard let name = SwiftURLName.normalize(url) else { return true }
            return [name, SwiftURLName.repositoryName(of: name)].compactMap { $0 }.contains {
                finding.advisory.affects(version, packageName: $0)
            }
        case .registry:
            return finding.advisory.affects(version, packageName: nil)
        case .local:
            return true
        }
    }

    /// Classifies a package pinned to a branch or revision, which is only fixed by requiring a patched version.
    ///
    /// A root that depends on it can change its requirement; otherwise the packages depending on it must.
    private func unversionedClassification(of identity: PackageIdentity) -> FixClassification {
        let parents = self.graph.packages.filter { $0.dependencies.contains(identity) }
        if parents.contains(where: { self.graph.isRootPackage($0) }) {
            return .manifest
        }
        return .upstream(blockedBy: Self.sortedUnique(parents.map(\.manifest.displayName)))
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
