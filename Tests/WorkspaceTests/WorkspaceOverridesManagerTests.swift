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
import Testing
import _InternalTestSupport
@testable import Workspace

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceOverridesManagerTests {
    // MARK: - add

    /// Adding an override to a workspace with no existing overrides
    /// file creates the file, its parent directory, and writes a
    /// one-entry document that the parser round-trips.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func add_toMissingFile_createsFileWithEntry() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)
        let override = Self.makeOverride(identity: "some-lib", root: workspaceRoot)

        try WorkspaceOverridesManager.add(
            override: override,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        try #require(fileSystem.exists(overridesFile))
        let parsed = try WorkspaceOverridesJSONParser.parse(
            v1: try fileSystem.readFileContents(overridesFile),
            workspaceRoot: workspaceRoot,
        )
        #expect(parsed == [override])
    }

    /// Adding an override for an identity that's already overridden
    /// replaces the existing entry — the file grows/shrinks correctly
    /// and there are no duplicate identities.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func add_whenIdentityAlreadyOverridden_replacesEntry() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)
        let first = Self.makeOverride(identity: "some-lib", relativePath: "old", root: workspaceRoot)
        let second = Self.makeOverride(identity: "some-lib", relativePath: "new", root: workspaceRoot)

        try WorkspaceOverridesManager.add(
            override: first,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        try WorkspaceOverridesManager.add(
            override: second,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        let parsed = try WorkspaceOverridesJSONParser.parse(
            v1: try fileSystem.readFileContents(overridesFile),
            workspaceRoot: workspaceRoot,
        )
        #expect(parsed == [second])
    }

    // MARK: - remove

    /// Removing an override drops the matching entry and rewrites
    /// the file with the remaining entries.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func remove_whenIdentityPresent_dropsEntry() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)
        let some = Self.makeOverride(identity: "some-lib", root: workspaceRoot)
        let other = Self.makeOverride(identity: "other-lib", root: workspaceRoot)
        try WorkspaceOverridesManager.add(
            override: some,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        try WorkspaceOverridesManager.add(
            override: other,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        try WorkspaceOverridesManager.remove(
            identity: .plain("some-lib"),
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        let parsed = try WorkspaceOverridesJSONParser.parse(
            v1: try fileSystem.readFileContents(overridesFile),
            workspaceRoot: workspaceRoot,
        )
        #expect(parsed == [other])
    }

    /// Removing the last override deletes the file rather than
    /// leaving it as a v1 doc with an empty `overrides` array. An
    /// empty file is a residual git-diff hazard; deleting it
    /// restores the pre-override baseline exactly.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func remove_whenLastEntry_deletesFile() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)
        let some = Self.makeOverride(identity: "some-lib", root: workspaceRoot)
        try WorkspaceOverridesManager.add(
            override: some,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        try WorkspaceOverridesManager.remove(
            identity: .plain("some-lib"),
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        #expect(fileSystem.exists(overridesFile) == false)
    }

    /// Removing an identity that isn't currently overridden throws
    /// the mutation error (already unit-tested at the pure-helper
    /// level). Here we just verify the manager propagates it and
    /// leaves the file untouched.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func remove_whenIdentityAbsent_throwsAndPreservesFile() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)
        let some = Self.makeOverride(identity: "some-lib", root: workspaceRoot)
        try WorkspaceOverridesManager.add(
            override: some,
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
        let beforeContent: String = try fileSystem.readFileContents(overridesFile)

        #expect(throws: WorkspaceOverridesMutationError.identityNotOverridden("ghost-lib")) {
            try WorkspaceOverridesManager.remove(
                identity: .plain("ghost-lib"),
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: fileSystem,
            )
        }
        let afterContent: String = try fileSystem.readFileContents(overridesFile)
        #expect(beforeContent == afterContent)
    }

    // MARK: - list

    /// `list` returns an empty array when the overrides file
    /// doesn't exist — parallel to how `loadIfPresent` treats a
    /// missing file. The CLI turns this into the "no overrides
    /// declared" hint.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func list_whenFileMissing_returnsEmpty() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)

        let result = try WorkspaceOverridesManager.list(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        #expect(result.isEmpty)
    }

    /// `list` returns entries sorted by identity regardless of the
    /// order they were `add`ed. Locks in the output ordering the CLI
    /// displays.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func list_whenFilePresent_returnsEntriesSortedByIdentity() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)
        // Insert deliberately out of order.
        for identity in ["gamma", "alpha", "beta"] {
            try WorkspaceOverridesManager.add(
                override: Self.makeOverride(identity: identity, root: workspaceRoot),
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: fileSystem,
            )
        }

        let result = try WorkspaceOverridesManager.list(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        #expect(result.map { $0.identity.description } == ["alpha", "beta", "gamma"])
    }

    // MARK: - helpers

    private static func makeOverride(
        identity: String,
        relativePath: String? = nil,
        root: AbsolutePath,
    ) -> WorkspaceOverridesJSONParser.Override {
        let path = relativePath ?? "external/\(identity)"
        return WorkspaceOverridesJSONParser.Override(
            identity: .plain(identity),
            overridingDependency: .fileSystem(
                identity: .plain(identity),
                nameForTargetDependencyResolutionOnly: nil,
                path: root.appending(try! RelativePath(validating: path)),
                productFilter: .everything,
                traits: nil,
            ),
        )
    }
}
