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
import PackageAudit
import PackageGraph
import PackageModel
import SwiftParser
import SwiftSyntax
import Workspace

import struct TSCBasic.ByteString
import protocol TSCBasic.WritableByteStream
import var TSCBasic.stderrStream
import var TSCBasic.stdoutStream
import struct TSCUtility.Version

extension SwiftPackageCommand.Audit {
    struct Fix: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "fix",
            abstract: "Upgrade dependencies with known security vulnerabilities.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var options: AuditOptions

        @Flag(help: "Show the planned changes without applying them.")
        var dryRun: Bool = false

        @Flag(help: "Allow changing dependency requirements in the root Package.swift.")
        var allowManifestChanges: Bool = false

        @Flag(help: "With --allow-manifest-changes, allow requirement changes that cross a major version.")
        var allowMajorUpgrades: Bool = false

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let (report, graph, workspace, root) = try await SwiftPackageCommand.Audit.runAudit(
                options: self.options,
                swiftCommandState: swiftCommandState
            )
            // Keep standard output a single JSON document in JSON mode.
            let progress: WritableByteStream = self.options.format == .json ? stderrStream : stdoutStream
            func say(_ line: String) {
                progress.send(line + "\n")
                progress.flush()
            }

            let plan = try self.makePlan(report: report, graph: graph, fileSystem: swiftCommandState.fileSystem)
            let oldPins = try workspace.resolvedPackagesStore.load().resolvedPackages
            let updateIdentities = plan.updates.map(\.identity.description)
                + plan.manifestChanges.map(\.package.identity.description)

            if self.dryRun {
                if !plan.updates.isEmpty {
                    let scope = swiftCommandState.observabilityScope.makeChildScope(
                        description: "Planning dependency updates"
                    )
                    let changes = try await workspace.updateDependencies(
                        root: root,
                        packages: plan.updates.map(\.identity.description),
                        dryRun: true,
                        observabilityScope: scope
                    )
                    guard let changes, !scope.errorsReported else {
                        throw ExitCode.failure
                    }
                    for line in Self.updateLines(changes, oldPins: oldPins, report: report, verb: "Would update") {
                        say(line)
                    }
                }
                for change in plan.manifestChanges {
                    say("Would change requirement on \(change.location) in \(change.manifestPath.basename): \(change.from) -> \(change.to)")
                }
                for line in plan.skipped {
                    say(line)
                }
                if plan.isEmpty {
                    say("Nothing to fix.")
                }
                if self.options.format == .json {
                    try SwiftPackageCommand.Audit.printReport(report, options: self.options, swiftCommandState: swiftCommandState)
                }
                try SwiftPackageCommand.Audit.exitForReport(report, options: self.options, swiftCommandState: swiftCommandState)
                return
            }

            for line in plan.skipped {
                say(line)
            }
            guard !updateIdentities.isEmpty else {
                try SwiftPackageCommand.Audit.printReport(report, options: self.options, swiftCommandState: swiftCommandState)
                try SwiftPackageCommand.Audit.exitForReport(report, options: self.options, swiftCommandState: swiftCommandState)
                return
            }

            let changes = try await self.apply(
                plan,
                packages: updateIdentities,
                workspace: workspace,
                root: root,
                swiftCommandState: swiftCommandState
            )
            for change in plan.manifestChanges {
                say("Changed requirement on \(change.location) in \(change.manifestPath.basename): \(change.from) -> \(change.to)")
            }
            for line in Self.updateLines(changes, oldPins: oldPins, report: report, verb: "Updated") {
                say(line)
            }

            let (remaining, _, _, _) = try await SwiftPackageCommand.Audit.runAudit(
                options: self.options,
                swiftCommandState: swiftCommandState
            )
            try SwiftPackageCommand.Audit.printReport(remaining, options: self.options, swiftCommandState: swiftCommandState)
            try SwiftPackageCommand.Audit.exitForReport(remaining, options: self.options, swiftCommandState: swiftCommandState)
        }

        /// Applies the manifest edits of `plan`, then updates `packages`. On any failure, the manifests and
        /// `Package.resolved` are restored to their previous contents and the failure is rethrown.
        private func apply(
            _ plan: Plan,
            packages: [String],
            workspace: Workspace,
            root: PackageGraphRootInput,
            swiftCommandState: SwiftCommandState
        ) async throws -> [(PackageReference, Workspace.PackageStateChange)] {
            let fileSystem = swiftCommandState.fileSystem
            let resolvedFile = workspace.location.resolvedVersionsFile
            var snapshots: [AbsolutePath: ByteString?] = [:]
            for path in Set(plan.manifestChanges.map(\.manifestPath)) {
                snapshots.updateValue(try fileSystem.readFileContents(path), forKey: path)
            }
            // A missing `Package.resolved` is recorded as `nil`, so that restoring it deletes the file.
            snapshots.updateValue(
                fileSystem.exists(resolvedFile) ? try fileSystem.readFileContents(resolvedFile) : nil,
                forKey: resolvedFile
            )

            do {
                for (path, manifest) in plan.manifests where !manifest.edits.isEmpty {
                    try manifest.edits.applyEdits(
                        to: fileSystem,
                        manifest: manifest.syntax,
                        manifestPath: path,
                        verbose: false
                    )
                }
                let scope = swiftCommandState.observabilityScope.makeChildScope(
                    description: "Updating vulnerable dependencies"
                )
                let changes = try await workspace.updateDependencies(
                    root: root,
                    packages: packages,
                    observabilityScope: scope
                )
                guard let changes, !scope.errorsReported else {
                    throw ExitCode.failure
                }
                return changes
            } catch {
                for (path, contents) in snapshots {
                    if let contents {
                        try fileSystem.writeFileContents(path, bytes: contents)
                    } else if fileSystem.exists(path) {
                        try fileSystem.removeFileTree(path)
                    }
                }
                stderrStream.send("Restored \(snapshots.keys.map(\.basename).sorted().joined(separator: " and ")) since the dependencies could not be updated.\n")
                stderrStream.flush()
                throw error
            }
        }

        /// Lines describing the version changes in `changes`, relative to `oldPins`.
        private static func updateLines(
            _ changes: [(PackageReference, Workspace.PackageStateChange)],
            oldPins: ResolvedPackagesStore.ResolvedPackages,
            report: AuditReport,
            verb: String
        ) -> [String] {
            changes.compactMap { reference, change in
                guard case .updated(let state) = change, case .version(let new) = state.requirement else {
                    return nil
                }
                let old = oldPins[reference.identity].map { " \($0.state)" } ?? ""
                return "\(verb) \(Self.location(of: reference, report: report))\(old) -> \(new) (Package.resolved)"
            }
        }

        /// The location of `reference`, written as in the report when it has a finding.
        private static func location(of reference: PackageReference, report: AuditReport) -> String {
            if let finding = report.findings.first(where: { $0.package.identity == reference.identity }) {
                return Self.location(of: finding.package)
            }
            switch reference.kind {
            case .registry(let identity): return identity.description
            default: return reference.locationString
            }
        }
    }
}

// MARK: - Planning

extension SwiftPackageCommand.Audit.Fix {
    struct ManifestChange {
        var package: AuditedPackage
        var location: String
        var manifestPath: AbsolutePath
        var from: String
        var to: Version
    }

    struct ParsedManifest {
        var syntax: SourceFileSyntax
        var edits: [SourceEdit] = []
    }

    struct Plan {
        /// Packages to update within their current requirements.
        var updates: [AuditedPackage] = []
        /// Requirements to change in root manifests; their packages are updated as well.
        var manifestChanges: [ManifestChange] = []
        /// Root manifests with the edits to apply to them.
        var manifests: [AbsolutePath: ParsedManifest] = [:]
        /// Descriptions of the findings that are not fixed.
        var skipped: [String] = []

        var isEmpty: Bool {
            self.updates.isEmpty && self.manifestChanges.isEmpty && self.skipped.isEmpty
        }
    }

    /// Decides, for each package with findings at or above the threshold, how it is fixed or why it is not.
    private func makePlan(report: AuditReport, graph: ModulesGraph, fileSystem: any FileSystem) throws -> Plan {
        var plan = Plan()

        var order: [PackageIdentity] = []
        var findingsByPackage: [PackageIdentity: [AuditFinding]] = [:]
        for finding in report.findings where !finding.ignored && finding.severity.meets(self.options.severityThreshold) {
            if findingsByPackage[finding.package.identity] == nil {
                order.append(finding.package.identity)
            }
            findingsByPackage[finding.package.identity, default: []].append(finding)
        }

        for identity in order {
            let findings = findingsByPackage[identity] ?? []
            guard let package = findings.first?.package else { continue }
            let description = "\(Self.location(of: package))\(Self.version(of: package))"

            for finding in findings where finding.fixClassification == FixClassification.none {
                plan.skipped.append("Cannot fix \(description): no patched version of \(finding.advisory.id) is available.")
            }
            let fixable = findings.filter { !$0.fixedVersions.isEmpty }
            // The classifier gives all fixable findings of a package the same classification.
            guard let classification = fixable.first?.fixClassification else { continue }

            switch classification {
            case .update:
                plan.updates.append(package)
            case .manifest:
                // The lowest version that is at or above the lowest fix of every finding.
                guard let target = fixable.compactMap({ $0.fixedVersions.min() }).max() else { continue }
                var missingFlags: [String] = []
                if !self.allowManifestChanges {
                    missingFlags.append("--allow-manifest-changes")
                }
                if case .version(let pinned) = package.state, target.major > pinned.major, !self.allowMajorUpgrades {
                    missingFlags.append("--allow-major-upgrades")
                }
                if !missingFlags.isEmpty {
                    plan.skipped.append(
                        "Cannot fix \(description): the patched version \(target) is outside the requirement in Package.swift; re-run with \(missingFlags.joined(separator: " ")) to update it."
                    )
                    continue
                }
                if let reason = try self.planManifestChange(
                    for: package,
                    to: target,
                    graph: graph,
                    fileSystem: fileSystem,
                    plan: &plan
                ) {
                    plan.skipped.append("Cannot fix \(description): \(reason)")
                }
            case .upstream(let blockedBy):
                if blockedBy.isEmpty {
                    plan.skipped.append(
                        "Cannot fix \(description): no resolution avoids the vulnerable versions within current requirements."
                    )
                } else {
                    plan.skipped.append(
                        "Cannot fix \(description): the patched versions are excluded by the requirements of \(blockedBy.joined(separator: ", "))."
                    )
                }
            case .none:
                break
            }
        }
        return plan
    }

    /// Adds the edit raising the requirement on `package` to `target` to `plan`, or returns why it cannot be made.
    private func planManifestChange(
        for package: AuditedPackage,
        to target: Version,
        graph: ModulesGraph,
        fileSystem: any FileSystem,
        plan: inout Plan
    ) throws -> String? {
        guard let rootPackage = graph.rootPackages.first(where: { root in
            root.manifest.dependencies.contains { $0.identity == package.identity }
        }), let dependency = rootPackage.manifest.dependencies.first(where: { $0.identity == package.identity }) else {
            return "no root package declares a dependency on it."
        }
        let manifestPath = rootPackage.manifest.path

        if plan.manifests[manifestPath] == nil {
            let contents: ByteString = try fileSystem.readFileContents(manifestPath)
            let syntax = contents.withData { data in
                data.withUnsafeBytes { buffer in
                    buffer.withMemoryRebound(to: UInt8.self) { buffer in
                        Parser.parse(source: buffer)
                    }
                }
            }
            plan.manifests[manifestPath] = ParsedManifest(syntax: syntax)
        }
        guard let manifest = plan.manifests[manifestPath] else { return nil }

        var edits: [SourceEdit]?
        do {
            for locator in Self.locators(of: package, manifestDirectory: manifestPath.parentDirectory) {
                do {
                    edits = try ManifestRequirementEditor.raiseLowerBound(in: manifest.syntax, of: locator, to: target)
                    break
                } catch ManifestRequirementEditError.dependencyNotFound {
                    continue
                }
            }
        } catch let error as ManifestRequirementEditError {
            return "the requirement in \(manifestPath.basename) cannot be changed automatically: \(Self.describe(error))."
        }
        guard let edits else {
            return "the requirement in \(manifestPath.basename) cannot be changed automatically: \(Self.describe(.dependencyNotFound))."
        }
        guard !edits.isEmpty else {
            return "the requirement in \(manifestPath.basename) already starts at or above \(target)."
        }

        plan.manifests[manifestPath]?.edits += edits
        plan.manifestChanges.append(ManifestChange(
            package: package,
            location: Self.location(of: package),
            manifestPath: manifestPath,
            from: Self.lowerBound(of: dependency) ?? "?",
            to: target
        ))
        return nil
    }

    /// The ways the package may be written in a manifest: its location, and for a local repository also its path
    /// relative to the manifest, which is how such dependencies are usually declared.
    private static func locators(of package: AuditedPackage, manifestDirectory: AbsolutePath) -> [DependencyLocator] {
        switch package.kind {
        case .sourceControl(let url):
            var locators = [DependencyLocator.url(url)]
            // Local repositories are located by a `file://` URL or an absolute path.
            let pathString = url.hasPrefix("file://") ? String(url.dropFirst("file://".count)) : url
            if let path = try? AbsolutePath(validating: pathString),
               let resolvedPath = try? resolveSymlinks(path),
               let resolvedDirectory = try? resolveSymlinks(manifestDirectory)
            {
                locators.append(.url(path.pathString))
                locators.append(.url(resolvedPath.relative(to: resolvedDirectory).pathString))
            }
            return locators
        case .registry(let identity, _):
            return [.id(identity.description)]
        case .local:
            return []
        }
    }

    private static func lowerBound(of dependency: PackageDependency) -> String? {
        let requirement: PackageDependency.SourceControl.Requirement?
        switch dependency {
        case .sourceControl(let settings):
            requirement = settings.requirement
        case .registry(let settings):
            switch settings.requirement {
            case .exact(let version): return version.description
            case .range(let range): return range.lowerBound.description
            }
        case .fileSystem:
            requirement = nil
        }
        switch requirement {
        case .exact(let version): return version.description
        case .range(let range): return range.lowerBound.description
        default: return nil
        }
    }

    private static func describe(_ error: ManifestRequirementEditError) -> String {
        switch error {
        case .dependencyNotFound:
            "no `.package(...)` declaration of the dependency was found"
        case .ambiguousDependency:
            "the dependency is declared more than once"
        case .nonLiteralRequirement:
            "the requirement is not written as a string literal"
        case .unsupportedRequirement(let kind):
            "the requirement '\(kind)' cannot be raised"
        }
    }

    private static func location(of package: AuditedPackage) -> String {
        switch package.kind {
        case .sourceControl(let url): url
        case .registry(let identity, _): identity.description
        case .local(let path): path.pathString
        }
    }

    private static func version(of package: AuditedPackage) -> String {
        switch package.state {
        case .version(let version): " \(version)"
        case .revision(let revision): " \(revision)"
        case .none: ""
        }
    }
}
