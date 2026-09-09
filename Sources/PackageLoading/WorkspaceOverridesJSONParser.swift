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
import PackageModel

/// Errors surfaced by `WorkspaceOverridesJSONParser` when the
/// contents of `.swiftpm/configuration/workspace-overrides.json` are structurally
/// valid JSON but semantically invalid (unsupported schema version,
/// malformed dependency kind, unresolvable relative path, etc.).
public enum WorkspaceOverridesParseError: Error, Equatable {
    /// The `version` field in the overrides file does not match a
    /// version this SwiftPM understands. Overrides schemas are
    /// versioned so that additive changes (new dep kinds, new
    /// override targets) can roll out without silently downgrading
    /// older tooling.
    /// - Parameter version: The unknown version integer read from
    ///   the file.
    case unsupportedVersion(version: Int)

    /// An override entry declared a `.workspaceMember` or
    /// `.workspaceInherited` kind — workspace-scoped kinds cannot
    /// stand in for a concrete workspace-level dependency and are
    /// rejected at parse time. Only `.fileSystem`, `.sourceControl`,
    /// and `.registry` kinds are allowed as override targets.
    /// - Parameter identity: The identity of the offending override
    ///   entry (echoed back so users can locate it).
    case workspaceScopedKindNotAllowed(identity: String)
}

/// Errors surfaced when applying a parsed set of overrides to a
/// `WorkspaceManifest`. Distinct from `WorkspaceOverridesParseError`
/// because the parse and apply steps run in different phases and
/// produce different diagnostics.
public enum WorkspaceOverridesApplyError: Error, Equatable {
    /// An override entry references an identity that doesn't match
    /// any dependency in the workspace's declared `dependencies:`
    /// list. Overrides only replace existing workspace-level deps;
    /// adding new deps via the overrides file is not supported.
    /// - Parameter identity: The identity that failed to match, as
    ///   declared in the overrides file (echoed back so users can
    ///   locate it).
    case unknownIdentity(String)
}

/// Errors surfaced when mutating an `[Override]` list via the `add`
/// / `remove` helpers used by the `swift workspace override` CLI
/// subcommands. Kept separate from parse and apply errors so callers
/// can produce distinct diagnostics per phase.
public enum WorkspaceOverridesMutationError: Error, Equatable {
    /// `removeOverride(from:identity:)` was called with an identity
    /// that isn't currently overridden. Silently doing nothing would
    /// let typos hide; instead the CLI surfaces this as an
    /// actionable message ("no override for '<id>'; run
    /// `swift workspace override list` to see current entries").
    /// - Parameter identity: The identity that was requested for
    ///   removal.
    case identityNotOverridden(String)
}

/// Parses the contents of `.swiftpm/configuration/workspace-overrides.json` into
/// a resolved list of override entries ready for consumption by
/// `PackageWorkspace.loadWorkspaceManifest`.
///
/// The wire format mirrors the workspace-level `dependencies:` shape:
/// each entry carries an `identity` (used to match a workspace-level
/// dep in `Workspace.swift`) and a concrete `kind` (fileSystem /
/// sourceControl / registry) that replaces the declared dep at load
/// time.
public enum WorkspaceOverridesJSONParser {
    /// A single resolved override entry: which workspace-declared
    /// identity to replace, and the replacement `PackageDependency`.
    public struct Override: Equatable {
        /// The identity of the workspace-level dependency to replace.
        /// Must match one entry in `WorkspaceManifest.dependencies`;
        /// mismatches are surfaced as errors by the apply step (not
        /// here).
        public let identity: PackageIdentity

        /// The replacement dependency. Constructed with the same
        /// `PackageIdentity` as `identity` so the graph loader
        /// treats it as a drop-in substitute.
        public let overridingDependency: PackageDependency

        public init(
            identity: PackageIdentity,
            overridingDependency: PackageDependency,
        ) {
            self.identity = identity
            self.overridingDependency = overridingDependency
        }
    }

    // MARK: - Wire format

    private struct Input: Codable {
        let version: Int
        let overrides: [WireOverride]
    }

    private struct WireOverride: Codable {
        let identity: String
        let kind: Serialization.PackageDependency.Kind
    }

    // MARK: - Parsing

    /// Parses the v1 overrides schema.
    /// - Parameters:
    ///   - v1: The raw JSON contents of `.swiftpm/configuration/workspace-overrides.json`.
    ///   - workspaceRoot: The absolute path of the workspace root,
    ///     used to resolve relative paths in `.fileSystem` and
    ///     `.sourceControl` overrides.
    public static func parse(
        v1 jsonString: String,
        workspaceRoot: AbsolutePath,
    ) throws -> [Override] {
        let decoder = JSONDecoder.makeWithDefaults()
        let input = try decoder.decode(Input.self, from: jsonString)

        guard input.version == 1 else {
            throw WorkspaceOverridesParseError.unsupportedVersion(version: input.version)
        }

        return try input.overrides.map { wire in
            try Self.resolveOverride(wire, workspaceRoot: workspaceRoot)
        }
    }

    // MARK: - Loading from disk

    /// Reads the workspace-overrides file at `overridesFile` if it
    /// exists on disk, parses it, and returns the resolved overrides.
    /// When the file is absent this is a no-op that returns an empty
    /// array — the overrides file is entirely optional.
    ///
    /// The file's location is owned by the caller (typically
    /// `PackageWorkspace.DefaultLocations.workspaceOverridesFile(forRootPackage:)`);
    /// the parser only handles reading and parsing.
    ///
    /// - Parameters:
    ///   - overridesFile: The absolute path to the overrides file.
    ///   - workspaceRoot: The absolute path of the workspace root,
    ///     used to resolve any relative paths declared inside the
    ///     override entries (e.g. `.fileSystem` paths).
    ///   - fileSystem: The filesystem to read from.
    /// - Returns: The parsed overrides, or an empty array if the
    ///   file does not exist.
    public static func loadIfPresent(
        overridesFile: AbsolutePath,
        workspaceRoot: AbsolutePath,
        fileSystem: any FileSystem,
    ) throws -> [Override] {
        guard fileSystem.exists(overridesFile) else { return [] }
        let content: String = try fileSystem.readFileContents(overridesFile)
        return try parse(v1: content, workspaceRoot: workspaceRoot)
    }

    // MARK: - Applying

    /// Applies parsed overrides to a `WorkspaceManifest`, replacing
    /// entries in `manifest.dependencies` whose identity matches an
    /// override. Order in the manifest is preserved so the resolver
    /// sees a deterministic dependency list across resolves.
    ///
    /// Only `dependencies` is modified — `members`, `toolsVersion`,
    /// and `path` pass through untouched.
    ///
    /// - Parameters:
    ///   - overrides: The resolved overrides from `parse(v1:workspaceRoot:)`.
    ///   - manifest: The workspace manifest to override.
    /// - Returns: A new `WorkspaceManifest` with matching deps
    ///   replaced.
    /// - Throws: `WorkspaceOverridesApplyError.unknownIdentity` when
    ///   an override references an identity absent from
    ///   `manifest.dependencies`. Adding new deps via overrides is
    ///   not supported; unknown identities are almost always typos.
    public static func apply(
        _ overrides: [Override],
        to manifest: WorkspaceManifest,
    ) throws -> WorkspaceManifest {
        guard !overrides.isEmpty else { return manifest }

        var overridesByIdentity: [PackageIdentity: PackageDependency] = [:]
        for override in overrides {
            overridesByIdentity[override.identity] = override.overridingDependency
        }

        let declaredIdentities = Set(manifest.dependencies.map(\.identity))
        for override in overrides where !declaredIdentities.contains(override.identity) {
            throw WorkspaceOverridesApplyError.unknownIdentity(override.identity.description)
        }

        let newDependencies = manifest.dependencies.map { dep -> PackageDependency in
            guard let overriding = overridesByIdentity[dep.identity] else { return dep }
            return Self.substituting(overriding, preservingTraitsFrom: dep)
        }
        return WorkspaceManifest(
            path: manifest.path,
            toolsVersion: manifest.toolsVersion,
            members: manifest.members,
            dependencies: newDependencies,
        )
    }

    /// Applies parsed overrides to a workspace member's `Manifest`.
    /// Companion to `apply(_:to:)` for `WorkspaceManifest`; detailed
    /// contract semantics are filled in by later cycles.
    public static func apply(
        _ overrides: [Override],
        to memberManifest: Manifest,
    ) -> Manifest {
        return memberManifest
    }

    // MARK: - Mutating the override list

    /// Adds an override to a list, replacing any existing entry with
    /// the same identity. The insertion is idempotent: running the
    /// `swift workspace override add` CLI twice with the same
    /// identity but different targets updates the entry rather than
    /// producing a duplicate.
    ///
    /// The caller is responsible for validating that
    /// `override.identity` matches a declared workspace-level dep
    /// (see `WorkspaceManifest.dependencies`); the CLI wraps this
    /// with an identity-existence check to surface typos early.
    ///
    /// - Parameters:
    ///   - overrides: The current override list.
    ///   - override: The override entry to insert or replace.
    /// - Returns: The updated override list. Order is preserved for
    ///   entries not affected by the operation.
    public static func addOverride(
        to overrides: [Override],
        override: Override,
    ) -> [Override] {
        var result = overrides.filter { $0.identity != override.identity }
        result.append(override)
        return result
    }

    /// Removes the override with the given identity.
    ///
    /// - Parameters:
    ///   - overrides: The current override list.
    ///   - identity: The identity to remove.
    /// - Returns: The list with the matching entry removed.
    /// - Throws: `WorkspaceOverridesMutationError.identityNotOverridden`
    ///   when `identity` isn't currently overridden. A silent no-op
    ///   would let typos hide; instead the CLI surfaces this as an
    ///   actionable diagnostic.
    public static func removeOverride(
        from overrides: [Override],
        identity: PackageIdentity,
    ) throws -> [Override] {
        guard overrides.contains(where: { $0.identity == identity }) else {
            throw WorkspaceOverridesMutationError.identityNotOverridden(identity.description)
        }
        return overrides.filter { $0.identity != identity }
    }

    // MARK: - Dependency substitution

    /// Builds a new `PackageDependency` by combining the kind and all
    /// settings fields (`identity`, `location`, `requirement`,
    /// `productFilter`, etc.) from `overriding` with the `traits` from
    /// `original`. All fields other than `traits` are taken from
    /// `overriding`; only `traits` is preserved from `original`.
    private static func substituting(
        _ overriding: PackageDependency,
        preservingTraitsFrom original: PackageDependency,
    ) -> PackageDependency {
        switch overriding {
        case .fileSystem(let settings):
            return .fileSystem(
                identity: settings.identity,
                nameForTargetDependencyResolutionOnly: settings.nameForTargetDependencyResolutionOnly,
                path: settings.path,
                productFilter: settings.productFilter,
                traits: original.traits,
            )
        case .sourceControl(let settings):
            return .sourceControl(
                identity: settings.identity,
                nameForTargetDependencyResolutionOnly: settings.nameForTargetDependencyResolutionOnly,
                location: settings.location,
                requirement: settings.requirement,
                productFilter: settings.productFilter,
                traits: original.traits,
                registryIdentity: settings.registryIdentity,
            )
        case .registry(let settings):
            return .registry(
                identity: settings.identity,
                requirement: settings.requirement,
                productFilter: settings.productFilter,
                traits: original.traits,
            )
        case .workspaceMember, .workspaceInherited:
            return overriding
        }
    }

    // MARK: - Resolution

    private static func resolveOverride(
        _ wire: WireOverride,
        workspaceRoot: AbsolutePath,
    ) throws -> Override {
        let identity = PackageIdentity.plain(wire.identity)
        let dependency: PackageDependency
        switch wire.kind {
        case .fileSystem(let name, let path):
            let absolute: AbsolutePath
            if let abs = try? AbsolutePath(validating: path) {
                absolute = abs
            } else {
                let rel = try RelativePath(validating: path)
                absolute = workspaceRoot.appending(rel)
            }
            dependency = .fileSystem(
                identity: identity,
                nameForTargetDependencyResolutionOnly: name,
                path: absolute,
                productFilter: .everything,
                traits: nil,
            )
        case .sourceControl(let name, let location, let requirement):
            let scLocation: PackageDependency.SourceControl.Location
            if location.contains("://") {
                scLocation = .remote(SourceControlURL(location))
            } else if let abs = try? AbsolutePath(validating: location) {
                scLocation = .local(abs)
            } else {
                let rel = try RelativePath(validating: location)
                let abs = workspaceRoot.appending(rel)
                scLocation = .local(abs)
            }
            dependency = .sourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: name,
                location: scLocation,
                requirement: .init(requirement),
                productFilter: .everything,
                traits: nil,
                registryIdentity: nil,
            )
        case .registry(_, let requirement):
            dependency = .registry(
                identity: identity,
                requirement: .init(requirement),
                productFilter: .everything,
                traits: nil,
            )
        case .workspaceMember, .workspaceInherited:
            throw WorkspaceOverridesParseError.workspaceScopedKindNotAllowed(identity: wire.identity)
        }
        return Override(identity: identity, overridingDependency: dependency)
    }
}
