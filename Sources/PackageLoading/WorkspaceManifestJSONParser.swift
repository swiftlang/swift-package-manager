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

/// Errors surfaced by `WorkspaceManifestJSONParser` when the JSON emitted
/// by a `Workspace.swift` evaluation is structurally valid but semantically
/// invalid (e.g. no members, absolute member paths, duplicate identities).
public enum WorkspaceManifestParseError: Error, Equatable {
    /// The workspace declared no members. Workspaces must declare at
    /// least one member.
    case emptyMembers

    /// A member's path is absolute. Member paths must be relative to the
    /// directory containing `Workspace.swift`.
    /// - Parameters:
    ///   - memberName: The last path component of the offending member
    ///     (i.e. what the identity would have been).
    ///   - path: The offending absolute path as declared in `Workspace.swift`.
    case memberAbsolutePathError(memberName: String, path: String)

    /// Two or more members resolve to the same `PackageIdentity`, which is
    /// derived from the last path component of the member's path.
    /// - Parameter name: The duplicated identity name.
    case duplicateMembernames(name: String)

    /// The declared member path does not exist on disk.
    /// - Parameters:
    ///   - memberName: The last path component of the declared member (identity).
    ///   - path: The absolute filesystem path that was checked.
    case memberPathNotFound(memberName: String, path: String)

    /// The declared member's directory exists but contains no
    /// `Package.swift` manifest.
    /// - Parameters:
    ///   - memberName: The last path component of the declared member (identity).
    ///   - path: The absolute filesystem path of the member's directory.
    case memberMissingPackageManifest(memberName: String, path: String)

    /// A `Workspace.swift` sits in an ancestor of the discovered
    /// workspace root — SwiftPM doesn't support nested workspaces.
    /// The semantics of shared `.build/` / `Package.resolved` are
    /// undefined when two workspaces' trees overlap.
    /// - Parameters:
    ///   - inner: The workspace root discovered by walking up from
    ///     the invocation site.
    ///   - outer: The ancestor workspace root that also declares a
    ///     `Workspace.swift`.
    case nestedWorkspaceInAncestor(inner: AbsolutePath, outer: AbsolutePath)

    /// A workspace member's directory contains its own
    /// `Workspace.swift`. Same shared-state ambiguity as
    /// `nestedWorkspaceInAncestor`, but discovered by scanning
    /// members after the outer workspace loads.
    /// - Parameters:
    ///   - memberName: The identity of the offending member.
    ///   - nestedWorkspacePath: Absolute path of the stray
    ///     `Workspace.swift` inside the member.
    case nestedWorkspaceInMember(memberName: String, nestedWorkspacePath: AbsolutePath)
}

extension WorkspaceManifestParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyMembers:
            return "Workspace.swift declares no members; add at least one entry to the `members:` array"
        case .memberAbsolutePathError(let memberName, let path):
            return """
                member '\(memberName)' declares an absolute path '\(path)'; \
                member paths must be relative to the directory containing Workspace.swift
                """
        case .duplicateMembernames(let name):
            return """
                duplicate workspace member identity '\(name)'; two or more member paths \
                collide on the same last path component
                """
        case .memberPathNotFound(let memberName, let path):
            return """
                workspace member '\(memberName)' declared in Workspace.swift does not \
                exist at '\(path)'
                """
        case .memberMissingPackageManifest(let memberName, let path):
            return """
                workspace member '\(memberName)' at '\(path)' has no Package.swift manifest
                """
        case .nestedWorkspaceInAncestor(let inner, let outer):
            return """
                nested workspaces are not supported: Workspace.swift at \
                '\(inner.pathString)' is inside another workspace rooted at \
                '\(outer.pathString)'
                """
        case .nestedWorkspaceInMember(let memberName, let nestedWorkspacePath):
            return """
                nested workspaces are not supported: workspace member '\(memberName)' \
                contains its own Workspace.swift at '\(nestedWorkspacePath.pathString)'
                """
        }
    }
}

/// Parses the JSON emitted by a `Workspace.swift` manifest evaluation into
/// the resolved intermediate representation used by `PackageWorkspace`.
///
/// The evaluator (the compiled `Workspace.swift` binary) writes JSON to the
/// file descriptor passed via `-fileno`. This parser decodes that JSON,
/// resolves member paths relative to the workspace root into absolute
/// paths, and derives `PackageIdentity` for each member.
public enum WorkspaceManifestJSONParser {
    /// A resolved member, ready for consumption by `PackageWorkspace`.
    public struct Member {
        public let identity: PackageIdentity
        public let path: AbsolutePath
        public let ignoredStateDirectories: Set<WorkspaceManifest.StateDirectoryKind>

        public init(
            identity: PackageIdentity,
            path: AbsolutePath,
            ignoredStateDirectories: Set<WorkspaceManifest.StateDirectoryKind>,
        ) {
            self.identity = identity
            self.path = path
            self.ignoredStateDirectories = ignoredStateDirectories
        }
    }

    /// The parser's output. Does not include `path` or `toolsVersion`
    /// (which the caller supplies from context).
    public struct Result {
        public var members: [Member]
        public var dependencies: [PackageDependency]
    }

    // MARK: - Wire format

    private struct Input: Codable {
        let workspace: Serialization.Workspace
        let errors: [String]
    }

    private struct VersionedInput: Codable {
        let version: Int
    }

    // MARK: - Parsing

    public static func parse(
        v2 jsonString: String,
        workspaceRoot: AbsolutePath,
    ) throws -> Result {
        let decoder = JSONDecoder.makeWithDefaults()

        let versionedInput: VersionedInput
        do {
            versionedInput = try decoder.decode(VersionedInput.self, from: jsonString)
        } catch {
            throw ManifestParseError.unsupportedVersion(
                version: 1,
                underlyingError: "\(error.interpolationDescription)",
            )
        }
        guard versionedInput.version == 2 else {
            throw ManifestParseError.unsupportedVersion(version: versionedInput.version)
        }

        let input = try decoder.decode(Input.self, from: jsonString)

        guard input.errors.isEmpty else {
            throw ManifestParseError.runtimeManifestErrors(input.errors)
        }

        guard !input.workspace.members.isEmpty else {
            throw WorkspaceManifestParseError.emptyMembers
        }

        let members = try input.workspace.members.map { serialized in
            try Self.resolveMember(serialized, workspaceRoot: workspaceRoot)
        }

        try Self.rejectDuplicateIdentities(in: members)

        let dependencies = try input.workspace.dependencies.map { serialized in
            try Self.parseWorkspaceDependency(serialized, workspaceRoot: workspaceRoot)
        }

        return Result(
            members: members,
            dependencies: dependencies,
        )
    }

    /// Converts a workspace-level `Serialization.PackageDependency` into
    /// a model `PackageDependency`.
    ///
    /// The three concrete kinds (`.fileSystem`, `.sourceControl`,
    /// `.registry`) are accepted. Workspace-scoped kinds
    /// (`.workspaceMember`, `.workspaceInherited`) are rejected — a
    /// workspace's own `dependencies:` list cannot recursively refer to
    /// workspace-scoped kinds.
    private static func parseWorkspaceDependency(
        _ serialized: Serialization.PackageDependency,
        workspaceRoot: AbsolutePath,
    ) throws -> PackageDependency {
        let traits = serialized.traits.flatMap {
            Set($0.map(PackageDependency.Trait.init))
        }
        switch serialized.kind {
        case .fileSystem(let name, let path):
            let absolute: AbsolutePath
            if let abs = try? AbsolutePath(validating: path) {
                absolute = abs
            } else {
                let rel = try RelativePath(validating: path)
                absolute = workspaceRoot.appending(rel)
            }
            return .fileSystem(
                identity: PackageIdentity(path: absolute),
                nameForTargetDependencyResolutionOnly: name,
                path: absolute,
                productFilter: .everything,
                traits: traits,
            )
        case .sourceControl(let name, let location, let requirement):
            let scLocation: PackageDependency.SourceControl.Location
            let identity: PackageIdentity
            if location.contains("://") {
                scLocation = .remote(SourceControlURL(location))
                identity = PackageIdentity(urlString: location)
            } else if let abs = try? AbsolutePath(validating: location) {
                scLocation = .local(abs)
                identity = PackageIdentity(path: abs)
            } else {
                let rel = try RelativePath(validating: location)
                let abs = workspaceRoot.appending(rel)
                scLocation = .local(abs)
                identity = PackageIdentity(path: abs)
            }
            return .sourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: name,
                location: scLocation,
                requirement: .init(requirement),
                productFilter: .everything,
                traits: traits,
                registryIdentity: nil,
            )
        case .registry(let id, let requirement):
            return .registry(
                identity: .plain(id),
                requirement: .init(requirement),
                productFilter: .everything,
                traits: traits,
            )
        case .workspaceMember(let identity):
            throw ManifestParseError.runtimeManifestErrors([
                "Workspace.swift `dependencies:` entry uses `.package(workspaceMember: \"\(identity)\")`, which is not allowed at the workspace level. `.package(workspaceMember:)` is a member-level API used by a member's Package.swift to depend on a sibling workspace member. The workspace's own `dependencies:` list must use concrete dependency kinds: `.package(path:)`, `.package(url:)`, or `.package(id:)`.",
            ])
        case .workspaceInherited(let identity):
            throw ManifestParseError.runtimeManifestErrors([
                "Workspace.swift `dependencies:` entry uses `.package(workspaceInherited: \"\(identity)\")`, which is not allowed at the workspace level. `.package(workspaceInherited:)` is a member-level API used by a member's Package.swift to inherit a dependency declared in the workspace's `dependencies:` list. A workspace cannot inherit from itself; declare the dependency directly using `.package(path:)`, `.package(url:)`, or `.package(id:)`.",
            ])
        }
    }

    private static func resolveMember(
        _ serialized: Serialization.WorkspaceMember,
        workspaceRoot: AbsolutePath,
    ) throws -> Member {
        let relative: RelativePath
        do {
            relative = try RelativePath(validating: serialized.path)
        } catch {
            let last = (serialized.path as NSString).lastPathComponent
            throw WorkspaceManifestParseError.memberAbsolutePathError(
                memberName: last,
                path: serialized.path,
            )
        }
        let absolute = workspaceRoot.appending(relative)
        return Member(
            identity: PackageIdentity(path: absolute),
            path: absolute,
            ignoredStateDirectories: Set(
                serialized.ignoredStateDirectories.map(Self.mapKind(_:))
            ),
        )
    }

    private static func rejectDuplicateIdentities(in members: [Member]) throws {
        var seen: Set<PackageIdentity> = []
        for member in members {
            let (inserted, _) = seen.insert(member.identity)
            if !inserted {
                throw WorkspaceManifestParseError.duplicateMembernames(
                    name: member.identity.description,
                )
            }
        }
    }

    private static func mapKind(
        _ kind: Serialization.WorkspaceStateDirectoryKind,
    ) -> WorkspaceManifest.StateDirectoryKind {
        switch kind {
        case .build: return .build
        case .packageResolved: return .packageResolved
        case .packages: return .packages
        case .swiftpmConfig: return .swiftpmConfig
        }
    }
}
