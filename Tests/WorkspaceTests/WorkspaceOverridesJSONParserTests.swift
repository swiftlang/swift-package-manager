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

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceOverridesJSONParserTests {
    /// An overrides file with no entries parses cleanly to an empty
    /// array. Confirms the schema tolerates the "empty but present"
    /// case — a user might comment out all their overrides but leave
    /// the file behind.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withEmptyOverrides_returnsEmptyArray() throws {
        let json = """
        {"version":1,"overrides":[]}
        """
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        #expect(result.isEmpty)
    }

    /// A single fileSystem override with a relative path is resolved
    /// against the workspace root, mirroring how workspace-level
    /// fileSystem `dependencies:` are resolved by
    /// `WorkspaceManifestJSONParser`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withRelativeFileSystemOverride_resolvesAgainstWorkspaceRoot() throws {
        let json = """
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"fileSystem":{"name":null,"path":"external/local-some-lib"}}}]}
        """
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: workspaceRoot.appending(components: "external", "local-some-lib"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let result = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.count == 1)
        #expect(result[0] == expected)
    }

    /// An absolute fileSystem path is passed through verbatim (no
    /// workspaceRoot prefix). Users occasionally point at a
    /// checkout outside the workspace tree during debugging.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withAbsoluteFileSystemOverride_preservesPath() throws {
        let json = """
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"fileSystem":{"name":null,"path":"/absolute/some-lib"}}}]}
        """
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: AbsolutePath("/absolute/some-lib"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let result = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.count == 1)
        #expect(result[0] == expected)
    }

    /// A sourceControl override with a URL location and version
    /// requirement parses to a remote sourceControl dep. The
    /// override's identity — as declared by the user — replaces the
    /// identity that would otherwise be derived from the URL.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withSourceControlOverride_parsesAsRemote() throws {
        let json = #"""
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"sourceControl":{"name":null,"location":"https://fork.example.com/some-lib","requirement":{"branch":{"_0":"dev"}}}}}]}
        """#
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .sourceControl(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                location: .remote(SourceControlURL("https://fork.example.com/some-lib")),
                requirement: .branch("dev"),
                productFilter: .everything,
                traits: nil,
                registryIdentity: nil,
            ),
        )

        let result = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.count == 1)
        #expect(result[0] == expected)
    }

    /// A registry override carries the target's identity through
    /// verbatim; the parsed dependency's identity is the override's
    /// declared identity, not the wire-format `id` field (which is
    /// legacy naming from the shared `PackageDependency.Kind` enum).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withRegistryOverride_parsesAsRegistry() throws {
        let json = #"""
        {"version":1,"overrides":[{"identity":"scope.pkg","kind":{"registry":{"id":"scope.pkg","requirement":{"exact":{"_0":{"buildMetadataIdentifiers":[],"major":1,"minor":2,"patch":3,"prereleaseIdentifiers":[]}}}}}}]}
        """#
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("scope.pkg"),
            overridingDependency: .registry(
                identity: .plain("scope.pkg"),
                requirement: .exact("1.2.3"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let result = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.count == 1)
        #expect(result[0] == expected)
    }

    /// A schema-version bump the parser doesn't recognize is
    /// surfaced explicitly. This lets us extend the schema
    /// additively over time; older tooling reading a newer file
    /// gets a clear error rather than silently ignoring fields.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withUnknownSchemaVersion_throwsUnsupportedVersion() throws {
        let json = """
        {"version":99,"overrides":[]}
        """
        let workspaceRoot = AbsolutePath("/repo")

        #expect(throws: WorkspaceOverridesParseError.unsupportedVersion(version: 99)) {
            _ = try WorkspaceOverridesJSONParser.parse(
                v1: json,
                workspaceRoot: workspaceRoot,
            )
        }
    }

    /// A `.workspaceMember` or `.workspaceInherited` kind cannot
    /// stand in for a concrete override — those kinds only make
    /// sense at the member level. The parser rejects them so a
    /// mistake doesn't silently produce a broken graph.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withWorkspaceScopedKind_throws() throws {
        let json = """
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"workspaceMember":{"identity":"some-lib"}}}]}
        """
        let workspaceRoot = AbsolutePath("/repo")

        #expect(throws: WorkspaceOverridesParseError.workspaceScopedKindNotAllowed(identity: "some-lib")) {
            _ = try WorkspaceOverridesJSONParser.parse(
                v1: json,
                workspaceRoot: workspaceRoot,
            )
        }
    }

    // MARK: - apply

    /// An empty overrides list is a no-op: the returned manifest's
    /// dependencies are byte-identical to the input's. Establishes
    /// the identity element of the apply operation.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_withEmptyOverrides_returnsDependenciesUnchanged() throws {
        let dependencies = [
            Self.fileSystemDep(identity: "some-lib", relativePath: "external/some-lib"),
        ]
        let manifest = Self.makeManifest(dependencies: dependencies)

        let actual = try WorkspaceOverridesJSONParser.apply([], to: manifest)

        #expect(actual.dependencies == dependencies)
    }

    /// A single override matching a workspace-level dep replaces
    /// that dep in place. Only the dependencies list is under test
    /// here — other manifest fields (members, toolsVersion, path)
    /// are pass-through concerns tested elsewhere.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_withSingleMatch_replacesDep() throws {
        let unchanged = Self.fileSystemDep(identity: "other-lib", relativePath: "external/other-lib")
        let manifest = Self.makeManifest(
            dependencies: [
                Self.fileSystemDep(identity: "some-lib", relativePath: "external/some-lib"),
                unchanged,
            ],
        )
        let replacement = Self.fileSystemDep(identity: "some-lib", relativePath: "external/local-some-lib")
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: replacement,
        )

        let actual = try WorkspaceOverridesJSONParser.apply([override], to: manifest)

        #expect(actual.dependencies == [replacement, unchanged])
    }

    /// Multiple overrides each match a distinct workspace-level dep
    /// and all get replaced. Verifies the apply step scales to the
    /// realistic multi-dep case, not just the single-match happy
    /// path.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_withMultipleMatches_replacesAll() throws {
        let manifest = Self.makeManifest(
            dependencies: [
                Self.fileSystemDep(identity: "some-lib", relativePath: "external/some-lib"),
                Self.fileSystemDep(identity: "other-lib", relativePath: "external/other-lib"),
            ],
        )
        let someReplacement = Self.fileSystemDep(identity: "some-lib", relativePath: "external/local-some-lib")
        let otherReplacement = Self.fileSystemDep(identity: "other-lib", relativePath: "external/local-other-lib")
        let overrides = [
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("some-lib"),
                overridingDependency: someReplacement,
            ),
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("other-lib"),
                overridingDependency: otherReplacement,
            ),
        ]

        let actual = try WorkspaceOverridesJSONParser.apply(overrides, to: manifest)

        #expect(actual.dependencies == [someReplacement, otherReplacement])
    }

    /// An override whose identity doesn't match any workspace-level
    /// dep is rejected. This is the guard-rail against typos: a
    /// silent no-op would let a broken override sit in the repo
    /// undetected. The error names the offending identity so users
    /// can find it in the JSON file.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_withUnknownIdentity_throws() throws {
        let manifest = Self.makeManifest(
            dependencies: [
                Self.fileSystemDep(identity: "some-lib", relativePath: "external/some-lib"),
            ],
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("ghost-lib"),
            overridingDependency: Self.fileSystemDep(identity: "ghost-lib", relativePath: "external/ghost"),
        )

        #expect(throws: WorkspaceOverridesApplyError.unknownIdentity("ghost-lib")) {
            _ = try WorkspaceOverridesJSONParser.apply([override], to: manifest)
        }
    }

    // MARK: - loadIfPresent

    /// When the overrides file is absent from disk, `loadIfPresent`
    /// returns an empty array. The overrides file is optional; a
    /// workspace without one must load cleanly with zero overhead.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func loadIfPresent_withMissingFile_returnsEmpty() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = workspaceRoot.appending(components: ".swiftpm", "configuration", "workspace-overrides.json")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(workspaceRoot, recursive: true)

        let result = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        #expect(result.isEmpty)
    }

    /// When the overrides file exists at
    /// `.swiftpm/configuration/workspace-overrides.json`, `loadIfPresent`
    /// reads, parses, and returns the resolved overrides. Locks in
    /// the canonical filename + directory so the doc-facing path is
    /// stable.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func loadIfPresent_withPresentFile_readsAndParses() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overridesFile = workspaceRoot.appending(components: ".swiftpm", "configuration", "workspace-overrides.json")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(
            overridesFile.parentDirectory,
            recursive: true,
        )
        try fileSystem.writeFileContents(
            overridesFile,
            string: """
                {"version":1,"overrides":[{"identity":"some-lib","kind":{"fileSystem":{"name":null,"path":"external/local-some-lib"}}}]}
                """,
        )
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: workspaceRoot.appending(components: "external", "local-some-lib"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let result = try WorkspaceOverridesJSONParser.loadIfPresent(
            overridesFile: overridesFile,
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )

        try #require(result.count == 1)
        #expect(result[0] == expected)
    }

    // MARK: - addOverride

    /// Appending an override for an identity not already overridden
    /// grows the list by one. This is the common case for `swift
    /// workspace override add` on a fresh workspace.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addOverride_toEmptyList_appendsEntry() throws {
        let override = Self.makeOverride(identity: "some-lib")

        let result = WorkspaceOverridesJSONParser.addOverride(
            to: [],
            override: override,
        )

        #expect(result == [override])
    }

    /// Adding an override for an identity that is already overridden
    /// replaces the existing entry rather than duplicating it. This
    /// makes `swift workspace override add` idempotent — running it
    /// twice with the same identity but a new target updates the
    /// entry rather than creating a corrupt list with two entries
    /// for the same identity.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addOverride_whenIdentityAlreadyOverridden_replacesEntry() throws {
        let existing = Self.makeOverride(identity: "some-lib", relativePath: "old")
        let replacement = Self.makeOverride(identity: "some-lib", relativePath: "new")

        let result = WorkspaceOverridesJSONParser.addOverride(
            to: [existing],
            override: replacement,
        )

        #expect(result == [replacement])
    }

    // MARK: - removeOverride

    /// Removing an override by identity drops the matching entry
    /// and leaves the rest untouched.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func removeOverride_whenIdentityPresent_dropsEntry() throws {
        let some = Self.makeOverride(identity: "some-lib")
        let other = Self.makeOverride(identity: "other-lib")

        let result = try WorkspaceOverridesJSONParser.removeOverride(
            from: [some, other],
            identity: .plain("some-lib"),
        )

        #expect(result == [other])
    }

    /// Removing an identity that isn't currently overridden is an
    /// error, not a silent no-op. The CLI turns this into an
    /// actionable message pointing users at the identity list.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func removeOverride_whenIdentityAbsent_throws() throws {
        let some = Self.makeOverride(identity: "some-lib")

        #expect(throws: WorkspaceOverridesMutationError.identityNotOverridden("ghost-lib")) {
            _ = try WorkspaceOverridesJSONParser.removeOverride(
                from: [some],
                identity: .plain("ghost-lib"),
            )
        }
    }

    // MARK: - test helpers

    private static func makeManifest(
        dependencies: [PackageDependency],
    ) -> WorkspaceManifest {
        WorkspaceManifest(
            path: AbsolutePath("/repo/Workspace.swift"),
            toolsVersion: .current,
            members: [],
            dependencies: dependencies,
        )
    }

    private static func fileSystemDep(
        identity: String,
        relativePath: String,
    ) -> PackageDependency {
        .fileSystem(
            identity: .plain(identity),
            nameForTargetDependencyResolutionOnly: nil,
            path: AbsolutePath("/repo").appending(try! RelativePath(validating: relativePath)),
            productFilter: .everything,
            traits: nil,
        )
    }

    private static func makeOverride(
        identity: String,
        relativePath: String? = nil,
    ) -> WorkspaceOverridesJSONParser.Override {
        let path = relativePath ?? "external/\(identity)"
        return WorkspaceOverridesJSONParser.Override(
            identity: .plain(identity),
            overridingDependency: Self.fileSystemDep(
                identity: identity,
                relativePath: path,
            ),
        )
    }
}
