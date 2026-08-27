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

import struct Basics.AbsolutePath
import protocol Basics.FileSystem
import enum PackageLoading.WorkspaceOverridesJSONParser
import enum PackageLoading.WorkspaceOverridesJSONWriter
import enum PackageLoading.WorkspaceOverridesMutationError
import struct PackageModel.PackageIdentity

/// File-level operations on `.swiftpm/configuration/workspace-overrides.json`.
///
/// Wraps `WorkspaceOverridesJSONParser` (read + mutate the parsed
/// list) and `WorkspaceOverridesJSONWriter` (serialize) to give the
/// `swift workspace override add | remove | list` CLI subcommands a
/// single call each — the CLI layer stays a thin argument-parsing
/// shell over these operations.
///
/// The manager takes an explicit `overridesFile: AbsolutePath` rather
/// than deriving it from `workspaceRoot`. This lets tests point at a
/// path on `InMemoryFileSystem` and matches the shape of the
/// underlying parser's `loadIfPresent`.
public enum WorkspaceOverridesManager {
    /// Adds an override to the on-disk overrides file. Creates the
    /// file (and its parent directory) if it doesn't exist yet.
    /// If `override.identity` is already present, the existing
    /// entry is replaced — the operation is idempotent.
    ///
    /// - Parameters:
    ///   - override: The override entry to insert or replace.
    ///   - overridesFile: The absolute path of the overrides file.
    ///   - workspaceRoot: The workspace root, used by the parser to
    ///     resolve any relative paths in already-persisted entries.
    ///   - fileSystem: The filesystem to read from and write to.
    public static func add(
        override: WorkspaceOverridesJSONParser.Override,
        overridesFile: AbsolutePath,
        workspaceRoot: AbsolutePath,
        fileSystem: any FileSystem,
    ) throws {
        let current = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        let updated = WorkspaceOverridesJSONParser.addOverride(
            to: current,
            override: override,
        )
        try Self.write(overrides: updated, to: overridesFile, fileSystem: fileSystem)
    }

    /// Removes the override with the given identity from the on-disk
    /// overrides file. When the removal empties the file, the file
    /// itself is deleted rather than left as `{"version":1,"overrides":[]}`
    /// — this restores the pre-override baseline exactly, which
    /// avoids residual git diffs.
    ///
    /// - Parameters:
    ///   - identity: The identity to remove.
    ///   - overridesFile: The absolute path of the overrides file.
    ///   - workspaceRoot: The workspace root.
    ///   - fileSystem: The filesystem to read from and write to.
    /// - Throws: `WorkspaceOverridesMutationError.identityNotOverridden`
    ///   when the identity isn't currently overridden. The on-disk
    ///   file is unchanged in that case.
    public static func remove(
        identity: PackageIdentity,
        overridesFile: AbsolutePath,
        workspaceRoot: AbsolutePath,
        fileSystem: any FileSystem,
    ) throws {
        let current = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        let updated = try WorkspaceOverridesJSONParser.removeOverride(
            from: current,
            identity: identity,
        )
        if updated.isEmpty {
            if fileSystem.exists(overridesFile) {
                try fileSystem.removeFileTree(overridesFile)
            }
        } else {
            try Self.write(overrides: updated, to: overridesFile, fileSystem: fileSystem)
        }
    }

    /// Returns the current overrides in the on-disk file, sorted by
    /// identity. Returns an empty array when the file doesn't exist
    /// (parallel to `WorkspaceOverridesJSONParser.loadIfPresent`).
    ///
    /// - Parameters:
    ///   - overridesFile: The absolute path of the overrides file.
    ///   - workspaceRoot: The workspace root.
    ///   - fileSystem: The filesystem to read from.
    /// - Returns: The overrides, alphabetized by identity.
    public static func list(
        overridesFile: AbsolutePath,
        workspaceRoot: AbsolutePath,
        fileSystem: any FileSystem,
    ) throws -> [WorkspaceOverridesJSONParser.Override] {
        let current = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        return current.sorted { $0.identity.description < $1.identity.description }
    }

    // MARK: - Private

    private static func write(
        overrides: [WorkspaceOverridesJSONParser.Override],
        to overridesFile: AbsolutePath,
        fileSystem: any FileSystem,
    ) throws {
        let parent = overridesFile.parentDirectory
        if !fileSystem.exists(parent) {
            try fileSystem.createDirectory(parent, recursive: true)
        }
        let content = try WorkspaceOverridesJSONWriter.writeV1(overrides: overrides)
        try fileSystem.writeFileContents(overridesFile, string: content)
    }
}
