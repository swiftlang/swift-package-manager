//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
@_spi(SwiftPMInternal) import CoreCommands
import Dispatch
import PackageModel
import PackageGraph
import Workspace

extension SwiftPackageCommand {
    struct Update: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update package dependencies.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(name: [.long, .customShort("n")],
              help: "Display the list of dependencies that can be updated.")
        var dryRun: Bool = false

        @Argument(help: "The packages to update.")
        var packages: [String] = []

        /// Restricts the update to the dependency subtree of the named
        /// workspace member. Overrides an implicit CWD-inside-member
        /// focus. When set with the positional `packages` argument,
        /// the positional filter is ignored in favour of the member's
        /// transitive dep set.
        @Option(
            name: .customLong("package"),
            help: "Restrict the update to the transitive dependency subtree of the named workspace member.",
        )
        var selectedPackage: PackageIdentity?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let workspace = try swiftCommandState.getActiveWorkspace()
            // Trigger workspace-root discovery up-front so
            // `currentWorkspaceMemberIdentities` and
            // `currentWorkspaceMemberFocus` are populated before the
            // focus decision reads them. `getWorkspaceRoot()` is the
            // side-effecting hook that assigns those fields on the
            // `SwiftCommandState`; without an explicit call here, both
            // are still nil at the point `computeUpdateFocus` runs and
            // `--package X` would spuriously report "requires a
            // Workspace.swift".
            let workspaceRoot = try await swiftCommandState.getWorkspaceRoot()

            let focus = Self.computeUpdateFocus(
                selectedPackage: self.selectedPackage,
                workspaceMemberFocus: swiftCommandState.currentWorkspaceMemberFocus,
                availableMemberIdentities: swiftCommandState.currentWorkspaceMemberIdentities,
                observabilityScope: swiftCommandState.observabilityScope,
            )
            guard swiftCommandState.observabilityScope.errorsReported == false else {
                throw ExitCode.failure
            }

            let updatePackages: [String]
            if let focus {
                // Compute the focused member's transitive dep identity
                // set from the loaded graph and pass it through as
                // `packages: [String]`. The resolver preserves pins for
                // identities outside this set.
                let graph = try await swiftCommandState.loadPackageGraph()
                let transitiveDeps = Self.computeTransitiveDepIdentities(
                    memberIdentity: focus,
                    graph: graph,
                )
                updatePackages = transitiveDeps.map { $0.description }.sorted()
            } else {
                updatePackages = self.packages
            }

            let changes = try await workspace.updateDependencies(
                root: workspaceRoot,
                packages: updatePackages,
                dryRun: dryRun,
                observabilityScope: swiftCommandState.observabilityScope
            )

            if self.dryRun, let changes = changes, let resolvedPackagesStore = swiftCommandState.observabilityScope.trap({ try workspace.resolvedPackagesStore.load() }){
                self.logPackageChanges(changes: changes, store: resolvedPackagesStore)
            }

            if !self.dryRun {
                // Throw if there were errors when loading the graph.
                // The actual errors will be printed before exiting.
                guard !swiftCommandState.observabilityScope.errorsReported else {
                    throw ExitCode.failure
                }
            }
        }

        /// Pure decision: resolves the update-scope focus from the
        /// mutually-composing sources (Slice 5 `--package` selector
        /// overrides Slice 4 CWD-inside-member focus). Returns nil
        /// when the update should be workspace-wide.
        ///
        /// Emits `.packageSelectorRequiresWorkspace` when `--package`
        /// is given outside a workspace, or `.unknownWorkspaceMember`
        /// when the identity isn't declared in the workspace — mirrors
        /// `BuildCommandOptions.computeBuildSubset`.
        static func computeUpdateFocus(
            selectedPackage: PackageIdentity?,
            workspaceMemberFocus: PackageIdentity?,
            availableMemberIdentities: Set<PackageIdentity>?,
            observabilityScope: ObservabilityScope,
        ) -> PackageIdentity? {
            if let selectedPackage {
                guard let availableMemberIdentities else {
                    observabilityScope.emit(
                        .packageSelectorRequiresWorkspace(requested: selectedPackage),
                    )
                    return nil
                }
                guard availableMemberIdentities.contains(selectedPackage) else {
                    observabilityScope.emit(
                        .unknownWorkspaceMember(
                            requested: selectedPackage,
                            known: availableMemberIdentities,
                        ),
                    )
                    return nil
                }
                return selectedPackage
            }
            return workspaceMemberFocus
        }

        /// Pure graph walk: given a workspace member's identity,
        /// collects every transitive dep identity by BFS'ing through
        /// `ModulesGraph.directDependencies(for:)`. Returns the empty
        /// set when the member has no deps or when the identity isn't
        /// present in the graph.
        static func computeTransitiveDepIdentities(
            memberIdentity: PackageIdentity,
            graph: ModulesGraph,
        ) -> Set<PackageIdentity> {
            guard let member = graph.package(for: memberIdentity) else {
                return []
            }
            var visited: Set<PackageIdentity> = []
            var queue: [ResolvedPackage] = graph.directDependencies(for: member)
            while let next = queue.first {
                queue.removeFirst()
                let identity = next.identity
                if visited.insert(identity).inserted {
                    queue.append(contentsOf: graph.directDependencies(for: next))
                }
            }
            return visited
        }

        private func logPackageChanges(changes: [(PackageReference, PackageWorkspace.PackageStateChange)], store: ResolvedPackagesStore) {
            let changes = changes.filter { $0.1 != .unchanged }

            var report = "[Dry-run] \(changes.count) dependenc\(changes.count == 1 ? "y would" : "ies would") change\(changes.count > 0 ? ":" : ".")"
            for (package, change) in changes {
                let currentVersion = store.resolvedPackages[package.identity]?.state.description ?? ""
                switch change {
                case let .added(state):
                    report += "\n"
                    report += "+ \(package.identity) \(state.requirement.prettyPrinted)"
                case let .updated(state):
                    report += "\n"
                    report += "~ \(package.identity) \(currentVersion) -> \(package.identity) \(state.requirement.prettyPrinted)"
                case .removed:
                    report += "\n"
                    report += "- \(package.identity) \(currentVersion)"
                case .unchanged:
                    continue
                }
            }

            print(report)
        }
    }
}
