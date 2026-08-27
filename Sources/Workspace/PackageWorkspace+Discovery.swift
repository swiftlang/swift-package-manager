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

        try Self.validateMembers(manifest.members, fileSystem: fileSystem)

        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let overrides = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        guard !overrides.isEmpty else {
            return manifest
        }
        observabilityScope.emit(
            info: "applying \(overrides.count) workspace dependency override(s) from \(overridesFile.pathString):",
        )
        for override in overrides {
            observabilityScope.emit(
                info: "  - \(override.identity): \(override.overridingDependency.locationString)",
            )
        }
        return try WorkspaceOverridesJSONParser.apply(overrides, to: manifest)
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
}
