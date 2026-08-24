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

        // Dependency resolution is deferred to Slice 3, where
        // `.package(workspaceInherited:)` semantics land. Slice 1 fixtures
        // declare no workspace-level dependencies.
        return Result(
            members: members,
            dependencies: [],
        )
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
