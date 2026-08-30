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
import PackageLoading
import PackageModel

extension PackageWorkspace {
    /// Walks up from `path` looking for a `Workspace.swift` file.
    ///
    /// Terminates at the filesystem root. Returns the directory containing
    /// the first `Workspace.swift` found, or `nil` if none is found before
    /// reaching the root.
    ///
    /// - Parameters:
    ///   - path: The directory to start the walk from. Typically the current
    ///     working directory of a SwiftPM command.
    ///   - fileSystem: The filesystem to query.
    /// - Returns: The absolute path of the workspace root directory, or
    ///   `nil` when no ancestor contains a `Workspace.swift`.
    public static func discoverWorkspaceRoot(
        from path: AbsolutePath,
        fileSystem: any FileSystem,
    ) -> AbsolutePath? {
        var current = path
        while true {
            let candidate = current.appending(WorkspaceManifest.filename)
            if fileSystem.exists(candidate) {
                return current
            }
            if current == .root { return nil }
            current = current.parentDirectory
        }
    }

    /// Returns the identity of the workspace member whose path is the
    /// closest ancestor of (or equal to) `cwd`.
    ///
    /// Used to implement "Case A": when a SwiftPM command is invoked
    /// from inside a workspace member's directory, the enclosing member
    /// is treated as the default focus for build/test/run.
    ///
    /// The comparison is purely syntactic. Callers that care about
    /// symlinks are expected to pass already-resolved (`realpath`)
    /// absolute paths for both `cwd` and each member.
    ///
    /// - Parameters:
    ///   - cwd: The current working directory (or any path being tested
    ///     for enclosure).
    ///   - members: The workspace's declared members.
    /// - Returns: The identity of the enclosing member, preferring the
    ///   deepest match when members are nested. `nil` when no member
    ///   encloses `cwd`.
    public static func findEnclosingMember(
        cwd: AbsolutePath,
        in members: [WorkspaceManifest.Member],
    ) -> PackageIdentity? {
        members
            .filter { $0.path.isAncestorOfOrEqual(to: cwd) }
            .max(by: { $0.path.pathString.count < $1.path.pathString.count })?
            .identity
    }

    /// Loads and validates the `Workspace.swift` manifest at `workspaceRoot`.
    ///
    /// Reads the tools-version header, invokes the manifest loader (which
    /// spawns the compiled manifest binary and returns parsed JSON), then
    /// applies filesystem-level invariants that the JSON parser cannot check:
    /// each declared member's path must exist and contain a `Package.swift`.
    ///
    /// - Note: New callers that need the parsed overrides alongside
    ///   the manifest should call `loadWorkspaceManifestAndOverrides`
    ///   directly.
    /// - Parameters:
    ///   - workspaceRoot: The directory containing `Workspace.swift`.
    ///   - manifestLoader: The manifest loader used to evaluate the manifest.
    ///   - fileSystem: The filesystem used for member existence checks.
    ///   - observabilityScope: Scope for diagnostics.
    /// - Returns: A fully-resolved `WorkspaceManifest`.
    public static func loadWorkspaceManifest(
        at workspaceRoot: AbsolutePath,
        manifestLoader: ManifestLoader,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
    ) async throws -> WorkspaceManifest {
        let (manifest, _) = try await Self.loadWorkspaceManifestAndOverrides(
            at: workspaceRoot,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
        )
        return manifest
    }

    /// Loads the `Workspace.swift` manifest at `workspaceRoot` and, alongside
    /// it, the parsed contents of any workspace-overrides file. The overrides
    /// are surfaced separately so they can be plumbed into
    /// `PackageGraphRootInput.overrides` and applied per-member during
    /// `loadRootManifests`.
    ///
    /// The workspace manifest itself already has its workspace-level
    /// dependencies rewritten by any matching overrides (preserving the
    /// pre-existing Phase 8B behaviour); the returned override list drives
    /// the member-level rewrite and the cross-scope identity validation
    /// added in Cycle 11.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The directory containing `Workspace.swift`.
    ///   - manifestLoader: The manifest loader used to evaluate the manifest.
    ///   - fileSystem: The filesystem used for member existence checks and
    ///     for reading the overrides file.
    ///   - observabilityScope: Scope for diagnostics.
    /// - Returns: A tuple containing the fully-resolved `WorkspaceManifest`
    ///   (with workspace-level overrides applied) and the parsed override
    ///   list (empty when no overrides file is present).
    public static func loadWorkspaceManifestAndOverrides(
        at workspaceRoot: AbsolutePath,
        manifestLoader: ManifestLoader,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
    ) async throws -> (
        manifest: WorkspaceManifest,
        overrides: [WorkspaceOverridesJSONParser.Override]
    ) {
        let manifestPath = workspaceRoot.appending(WorkspaceManifest.filename)

        let toolsVersion = try ToolsVersionParser.parse(
            manifestPath: manifestPath,
            fileSystem: fileSystem,
        )

        let manifest = try await manifestLoader.loadWorkspaceManifest(
            at: manifestPath,
            toolsVersion: toolsVersion,
            workspaceRoot: workspaceRoot,
            observabilityScope: observabilityScope,
        )

        try Self.validateWorkspace(
            manifest,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
        )

        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let overrides = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        guard !overrides.isEmpty else {
            return (manifest, overrides)
        }
        observabilityScope.emit(
            info: "applying \(overrides.count) workspace dependency override(s) from \(overridesFile.pathString):",
        )
        for override in overrides {
            observabilityScope.emit(
                info: "  - \(override.identity): \(override.overridingDependency.locationString)",
            )
        }
        return (WorkspaceOverridesJSONParser.apply(overrides, to: manifest), overrides)
    }

    /// Orchestrates every load-time check applied to a freshly-
    /// loaded `WorkspaceManifest` — nested-workspace prohibitions,
    /// per-member disk-state validation, and the out-of-tree
    /// portability warning. Throws on the first hard error; the
    /// out-of-tree warning is best-effort and never throws.
    ///
    /// The individual `check…` / `validateMembers` helpers stay
    /// separately-testable at unit-test level; this fn wires them
    /// together for `loadWorkspaceManifest` and any future callers
    /// that need the same load-time posture.
    package static func validateWorkspace(
        _ manifest: WorkspaceManifest,
        workspaceRoot: AbsolutePath,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
    ) throws {
        try Self.checkNestedWorkspaceInAncestors(
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        try Self.validateMembers(manifest.members, fileSystem: fileSystem)
        try Self.checkNestedWorkspaceInMembers(
            manifest.members,
            fileSystem: fileSystem,
        )
        Self.checkOutOfTreeMembers(
            manifest.members,
            workspaceRoot: workspaceRoot,
            observabilityScope: observabilityScope,
        )
    }

    private static func validateMembers(
        _ members: [WorkspaceManifest.Member],
        fileSystem: any FileSystem,
    ) throws {
        for member in members {
            guard fileSystem.isDirectory(member.path) else {
                throw WorkspaceManifestParseError.memberPathNotFound(
                    memberName: member.identity.description,
                    path: member.path.pathString,
                )
            }
            let packageManifest = member.path.appending("Package.swift")
            guard fileSystem.isFile(packageManifest) else {
                throw WorkspaceManifestParseError.memberMissingPackageManifest(
                    memberName: member.identity.description,
                    path: member.path.pathString,
                )
            }
        }
    }

    /// Emits an `.warning` diagnostic for each member whose path
    /// falls OUTSIDE the workspace's directory tree. Out-of-tree
    /// members are legal — SwiftPM supports them — but they reduce
    /// the workspace's portability: a checkout made from a
    /// different working copy may not find the member. Surfacing
    /// this at load time lets the author confirm the situation is
    /// intentional or restructure the layout.
    ///
    /// Pure with respect to disk state: only compares path values
    /// against `workspaceRoot`; no filesystem access. Exposed as a
    /// static so it can be unit-tested without spinning up a full
    /// manifest evaluation.
    package static func checkOutOfTreeMembers(
        _ members: [WorkspaceManifest.Member],
        workspaceRoot: AbsolutePath,
        observabilityScope: ObservabilityScope,
    ) {
        for member in members where !member.path.isDescendantOfOrEqual(to: workspaceRoot) {
            observabilityScope.emit(
                .memberOutsideWorkspaceTree(
                    memberIdentity: member.identity,
                    memberPath: member.path,
                    workspaceRoot: workspaceRoot,
                ),
            )
        }
    }

    /// Walks up from `workspaceRoot`'s parent to filesystem root
    /// looking for another `Workspace.swift`. Throws
    /// `WorkspaceManifestParseError.nestedWorkspaceInAncestor` when
    /// found — SwiftPM does not support nested workspaces because
    /// shared-state semantics (which workspace owns `.build/`,
    /// which `Package.resolved` is authoritative) become undefined
    /// when two workspace trees overlap.
    ///
    /// Called from `loadWorkspaceManifest` after the workspace root
    /// is discovered. Exposed as `package` so unit tests can drive
    /// it directly against an `InMemoryFileSystem`.
    package static func checkNestedWorkspaceInAncestors(
        workspaceRoot: AbsolutePath,
        fileSystem: any FileSystem,
    ) throws {
        var current = workspaceRoot
        while current != .root {
            let parent = current.parentDirectory
            let candidate = parent.appending(WorkspaceManifest.filename)
            if fileSystem.exists(candidate) {
                throw WorkspaceManifestParseError.nestedWorkspaceInAncestor(
                    inner: workspaceRoot,
                    outer: parent,
                )
            }
            current = parent
        }
    }

    /// Scans each member's directory (depth 1) for a stray
    /// `Workspace.swift`. Throws
    /// `WorkspaceManifestParseError.nestedWorkspaceInMember` on the
    /// first offender — same nested-workspace prohibition as
    /// `checkNestedWorkspaceInAncestors`, discovered downward from
    /// the outer workspace rather than upward.
    ///
    /// Depth 1 is sufficient for MVP: a `Workspace.swift` at the
    /// member's own root is the common misuse (someone accidentally
    /// nested a fresh `swift package workspace init` inside another
    /// workspace's member). Deeper scans have diminishing returns.
    package static func checkNestedWorkspaceInMembers(
        _ members: [WorkspaceManifest.Member],
        fileSystem: any FileSystem,
    ) throws {
        for member in members {
            let candidate = member.path.appending(WorkspaceManifest.filename)
            if fileSystem.exists(candidate) {
                throw WorkspaceManifestParseError.nestedWorkspaceInMember(
                    memberName: member.identity.description,
                    nestedWorkspacePath: candidate,
                )
            }
        }
    }
}

extension Basics.Diagnostic {
    /// Warning emitted when a workspace member's declared path
    /// resolves outside the directory tree containing
    /// `Workspace.swift`. Out-of-tree members work, but a workspace
    /// that references paths outside its own directory is less
    /// portable — the author may want to either accept the trade-
    /// off or restructure. Uses the concrete diagnostic factory
    /// pattern (rather than an inline string) so callers can
    /// reconstruct the message for assertions and downstream tools
    /// can pattern-match on the factory.
    @_spi(SwiftPMInternal)
    public static func memberOutsideWorkspaceTree(
        memberIdentity: PackageIdentity,
        memberPath: AbsolutePath,
        workspaceRoot: AbsolutePath,
    ) -> Self {
        .warning(
            """
            workspace member '\(memberIdentity)' at '\(memberPath.pathString)' is \
            outside the workspace directory tree rooted at '\(workspaceRoot.pathString)' \
            — this may reduce portability
            """,
        )
    }
}
