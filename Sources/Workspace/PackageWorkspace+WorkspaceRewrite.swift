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
import PackageModel

/// Errors raised by workspace-member dependency resolution and validation.
public enum WorkspaceResolveError: Error, Equatable {
    /// A member's `Package.swift` uses `.package(workspaceMember:)` but
    /// the named identity is not a declared member of the workspace.
    ///
    /// - Parameters:
    ///   - identity: The identity referenced by the member manifest.
    ///   - manifestPath: The path of the member's `Package.swift`.
    case unknownMember(identity: PackageIdentity, manifestPath: AbsolutePath)

    /// A `Package.swift` uses `.package(workspaceMember:)` but is being
    /// loaded outside a workspace context. This indicates the manifest
    /// author expected a `Workspace.swift` to be discoverable.
    ///
    /// - Parameter manifestPath: The path of the `Package.swift`.
    case workspaceMemberUsedOutsideWorkspace(manifestPath: AbsolutePath)
}

extension PackageWorkspace {
    /// Resolves the absolute path for each `.workspaceMember` dependency in
    /// a member manifest, using the workspace's member map.
    ///
    /// Runs after member manifests are loaded and before graph
    /// construction. The `.workspaceMember` case is preserved (not
    /// rewritten to `.fileSystem`); only its `WorkspaceMember.path`
    /// payload is augmented. Downstream code (resolver, graph builder,
    /// build system) handles `.workspaceMember` natively using the
    /// augmented path.
    ///
    /// - Parameters:
    ///   - manifest: The member's freshly-loaded `Manifest`.
    ///   - workspace: The workspace manifest whose members provide the
    ///     resolution map.
    /// - Returns: A copy of the manifest with `.workspaceMember` deps
    ///   augmented with resolved paths.
    /// - Throws: `WorkspaceResolveError.unknownMember` when a manifest
    ///   references a workspace-member identity that isn't declared in
    ///   `workspace.members`.
    public static func resolveWorkspaceMemberPaths(
        in manifest: Manifest,
        using workspace: WorkspaceManifest,
    ) throws -> Manifest {
        let memberMap: [PackageIdentity: AbsolutePath] = Dictionary(
            uniqueKeysWithValues: workspace.members.map { ($0.identity, $0.path) },
        )

        let resolved = try manifest.dependencies.map { dep -> PackageDependency in
            switch dep {
            case .workspaceMember(let member):
                guard let path = memberMap[member.identity] else {
                    throw WorkspaceResolveError.unknownMember(
                        identity: member.identity,
                        manifestPath: manifest.path,
                    )
                }
                return .workspaceMember(
                    PackageDependency.WorkspaceMember(
                        identity: member.identity,
                        path: path,
                        productFilter: member.productFilter,
                        traits: member.traits,
                    )
                )
            case .fileSystem, .sourceControl, .registry:
                return dep
            }
        }

        return manifest.withDependencies(resolved)
    }

    /// Validates that a manifest loaded outside a workspace context has no
    /// `.workspaceMember` dependencies.
    ///
    /// Called by `loadRootManifests` when `workspaceManifest` is `nil`.
    /// If any `.workspaceMember` dependency is present, the user has
    /// authored a `Package.swift` that expects a `Workspace.swift` to be
    /// discoverable but none was found.
    ///
    /// - Parameter manifest: The freshly-loaded manifest to validate.
    /// - Throws:
    ///   `WorkspaceResolveError.workspaceMemberUsedOutsideWorkspace` on
    ///   the first `.workspaceMember` dependency found.
    public static func validateNoWorkspaceMemberDependencies(
        in manifest: Manifest,
    ) throws {
        for dep in manifest.dependencies {
            if case .workspaceMember = dep {
                throw WorkspaceResolveError.workspaceMemberUsedOutsideWorkspace(
                    manifestPath: manifest.path,
                )
            }
        }
    }
}
