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

    /// A member's `Package.swift` uses `.package(workspaceInherited:)`
    /// but the named identity is not a declared dependency of the
    /// enclosing workspace.
    ///
    /// - Parameters:
    ///   - identity: The identity referenced by the member manifest.
    ///   - manifestPath: The path of the member's `Package.swift`.
    case unknownInheritedDependency(identity: PackageIdentity, manifestPath: AbsolutePath)

    /// A `Package.swift` uses `.package(workspaceInherited:)` but is
    /// being loaded outside a workspace context.
    ///
    /// - Parameter manifestPath: The path of the `Package.swift`.
    case workspaceInheritedUsedOutsideWorkspace(manifestPath: AbsolutePath)
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
            case .workspaceInherited(let inherited):
                return try Self.resolveInherited(
                    inherited,
                    workspace: workspace,
                    manifestPath: manifest.path,
                )
            case .fileSystem, .sourceControl, .registry:
                return dep
            }
        }

        return manifest.withDependencies(resolved)
    }

    /// Augments a `.workspaceInherited` dependency with the resolved
    /// concrete source (source-control URL/requirement, registry
    /// requirement, or file-system path) taken from the enclosing
    /// workspace's matching `dependencies:` entry. The `.workspaceInherited`
    /// case is preserved (not rewritten to `.sourceControl` / `.registry`
    /// / `.fileSystem`); only its `WorkspaceInherited.resolved` field is
    /// populated. Downstream code handles `.workspaceInherited` natively
    /// by reading `resolved`, treating it as if it were the concrete kind.
    ///
    /// Member-supplied traits are unioned with the workspace's traits;
    /// the member's `productFilter` is preserved on the outer
    /// `.workspaceInherited` case.
    private static func resolveInherited(
        _ inherited: PackageDependency.WorkspaceInherited,
        workspace: WorkspaceManifest,
        manifestPath: AbsolutePath,
    ) throws -> PackageDependency {
        guard let match = workspace.dependencies.first(where: { $0.identity == inherited.identity }) else {
            throw WorkspaceResolveError.unknownInheritedDependency(
                identity: inherited.identity,
                manifestPath: manifestPath,
            )
        }

        let unionedTraits: Set<PackageDependency.Trait>? = {
            switch (inherited.traits, match.traits) {
            case (nil, nil):
                return nil
            case (nil, let matchTraits?):
                return matchTraits
            case (let inheritedTraits?, nil):
                return inheritedTraits
            case (let inheritedTraits?, let matchTraits?):
                return inheritedTraits.union(matchTraits)
            }
        }()

        let resolved: PackageDependency.WorkspaceInherited.ResolvedInherited
        switch match {
        case .sourceControl(let sc):
            resolved = .sourceControl(
                location: sc.location,
                requirement: sc.requirement,
                nameForTargetDependencyResolutionOnly: sc.nameForTargetDependencyResolutionOnly,
                registryIdentity: sc.registryIdentity,
            )
        case .registry(let reg):
            resolved = .registry(requirement: reg.requirement)
        case .fileSystem(let fs):
            resolved = .fileSystem(
                path: fs.path,
                nameForTargetDependencyResolutionOnly: fs.nameForTargetDependencyResolutionOnly,
            )
        case .workspaceMember, .workspaceInherited:
            // Workspace dependencies must be concrete deps (source-control,
            // registry, or file-system) — not workspace-scoped kinds.
            // Encountering this indicates the workspace manifest itself
            // was authored with workspace-scoped deps, which is invalid.
            preconditionFailure(
                "workspace.dependencies must be concrete (.sourceControl, .registry, or .fileSystem); found \(match) for identity \(inherited.identity)"
            )
        }

        return .workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: inherited.identity,
                productFilter: inherited.productFilter,
                traits: unionedTraits,
                resolved: resolved,
            )
        )
    }

    /// Validates that a manifest loaded outside a workspace context has no
    /// `.workspaceMember` or `.workspaceInherited` dependencies.
    ///
    /// Called by `loadRootManifests` when `workspaceManifest` is `nil`.
    /// If any workspace-scoped dependency is present, the user has
    /// authored a `Package.swift` that expects a `Workspace.swift` to be
    /// discoverable but none was found.
    ///
    /// - Parameter manifest: The freshly-loaded manifest to validate.
    /// - Throws:
    ///   `WorkspaceResolveError.workspaceMemberUsedOutsideWorkspace` on
    ///   the first `.workspaceMember` dependency found, or
    ///   `WorkspaceResolveError.workspaceInheritedUsedOutsideWorkspace`
    ///   on the first `.workspaceInherited` dependency found.
    public static func validateNoWorkspaceMemberDependencies(
        in manifest: Manifest,
    ) throws {
        for dep in manifest.dependencies {
            switch dep {
            case .workspaceMember:
                throw WorkspaceResolveError.workspaceMemberUsedOutsideWorkspace(
                    manifestPath: manifest.path,
                )
            case .workspaceInherited:
                throw WorkspaceResolveError.workspaceInheritedUsedOutsideWorkspace(
                    manifestPath: manifest.path,
                )
            case .fileSystem, .sourceControl, .registry:
                continue
            }
        }
    }

    /// Returns the identities of workspace-level dependencies that no
    /// member inherits via `.package(workspaceInherited:)`.
    ///
    /// A workspace-level dependency is "used" iff at least one member's
    /// `Package.swift` declares `.package(workspaceInherited: <identity>)`
    /// for it. Concrete member deps that happen to share an identity
    /// (e.g. a vendored `.fileSystem` with the same identity as a
    /// workspace-declared dep) do NOT count as inheriting — the member
    /// is opting out of the workspace's version.
    ///
    /// Result order follows `workspace.dependencies` so warnings are
    /// deterministic.
    ///
    /// - Parameters:
    ///   - workspace: The workspace manifest.
    ///   - memberManifests: The resolved member manifests, as returned
    ///     by `loadRootManifests`.
    /// - Returns: The identities of workspace deps that no member
    ///   inherits. Empty when every workspace dep is inherited (or when
    ///   the workspace declares no dependencies).
    public static func findUnusedWorkspaceDependencies(
        workspace: WorkspaceManifest,
        memberManifests: [Manifest],
    ) -> [PackageIdentity] {
        var inheritedIdentities: Set<PackageIdentity> = []
        for member in memberManifests {
            for dep in member.dependencies {
                if case .workspaceInherited(let inherited) = dep {
                    inheritedIdentities.insert(inherited.identity)
                }
            }
        }

        return workspace.dependencies.compactMap { dep in
            inheritedIdentities.contains(dep.identity) ? nil : dep.identity
        }
    }
}
