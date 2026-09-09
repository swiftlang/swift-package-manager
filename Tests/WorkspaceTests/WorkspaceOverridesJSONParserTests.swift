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
import struct TSCUtility.Version

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

    /// A source-control override with an `.exact(Version)` requirement
    /// parses as a `.exact` requirement carrying the exact version.
    /// Complements the `.branch` coverage above with the requirement
    /// variant `swift package workspace override add url ... --exact`
    /// produces.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withSourceControlExactRequirement_parsesAsExact() throws {
        let json = #"""
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"sourceControl":{"name":null,"location":"https://fork.example.com/some-lib","requirement":{"exact":{"_0":{"buildMetadataIdentifiers":[],"major":1,"minor":2,"patch":3,"prereleaseIdentifiers":[]}}}}}}]}
        """#
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .sourceControl(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                location: .remote(SourceControlURL("https://fork.example.com/some-lib")),
                requirement: .exact("1.2.3"),
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

    /// A source-control override with a `.range(lowerBound..<upperBound)`
    /// requirement parses as a `.range` requirement. Locks in the
    /// wire format that `swift package workspace override add url ...
    /// --from X --to Y` writes to the overrides file.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withSourceControlRangeRequirement_parsesAsRange() throws {
        let json = #"""
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"sourceControl":{"name":null,"location":"https://fork.example.com/some-lib","requirement":{"range":{"lowerBound":{"buildMetadataIdentifiers":[],"major":1,"minor":0,"patch":0,"prereleaseIdentifiers":[]},"upperBound":{"buildMetadataIdentifiers":[],"major":2,"minor":0,"patch":0,"prereleaseIdentifiers":[]}}}}}}]}
        """#
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .sourceControl(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                location: .remote(SourceControlURL("https://fork.example.com/some-lib")),
                requirement: .range("1.0.0"..<"2.0.0"),
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

    /// A source-control override with a `.revision(String)` requirement
    /// parses as `.revision` carrying the commit SHA verbatim. This is
    /// the requirement variant `swift package workspace override add
    /// url ... --revision` produces.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withSourceControlRevisionRequirement_parsesAsRevision() throws {
        let json = #"""
        {"version":1,"overrides":[{"identity":"some-lib","kind":{"sourceControl":{"name":null,"location":"https://fork.example.com/some-lib","requirement":{"revision":{"_0":"abcdef0123456789"}}}}}]}
        """#
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .sourceControl(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                location: .remote(SourceControlURL("https://fork.example.com/some-lib")),
                requirement: .revision("abcdef0123456789"),
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

    /// A registry override with a `.range(lowerBound..<upperBound)`
    /// requirement parses as `.range`. Complements the `.exact`
    /// coverage above with the requirement variant `swift package
    /// workspace override add registry ... --from X --to Y` writes to
    /// the overrides file.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseV1_withRegistryRangeRequirement_parsesAsRange() throws {
        let json = #"""
        {"version":1,"overrides":[{"identity":"scope.pkg","kind":{"registry":{"id":"scope.pkg","requirement":{"range":{"lowerBound":{"buildMetadataIdentifiers":[],"major":1,"minor":0,"patch":0,"prereleaseIdentifiers":[]},"upperBound":{"buildMetadataIdentifiers":[],"major":2,"minor":0,"patch":0,"prereleaseIdentifiers":[]}}}}}}]}
        """#
        let workspaceRoot = AbsolutePath("/repo")
        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("scope.pkg"),
            overridingDependency: .registry(
                identity: .plain("scope.pkg"),
                requirement: .range("1.0.0"..<"2.0.0"),
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
    func apply_withEmptyOverrides_returnsDependenciesUnchanged() {
        let dependencies = [
            Self.fileSystemDep(identity: "some-lib", relativePath: "external/some-lib"),
        ]
        let manifest = Self.makeManifest(dependencies: dependencies)

        let actual = WorkspaceOverridesJSONParser.apply([], to: manifest)

        #expect(actual.dependencies == dependencies)
    }

    /// An empty overrides list passed to `apply(_:toMember:)` is a
    /// no-op: the returned `Manifest`'s dependencies are identical to
    /// the input member's. Establishes the identity-element contract.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withEmptyOverrides_returnsMemberDependenciesUnchanged() async throws {
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.fileSystemDep(identity: "lib-a", relativePath: "external/lib-a")],
        )

        let actual = WorkspaceOverridesJSONParser.apply([], to: member)

        #expect(actual.dependencies == member.dependencies)
    }

    /// A member manifest with an empty dependency list is unchanged by
    /// `apply(_:to:)` even when the overrides list is non-empty. The
    /// match loop is a no-op when there are no deps to rewrite —
    /// confirming no insertion or crash on the zero-deps path.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withZeroDeps_andNonEmptyOverrides_returnsMemberUnchanged() {
        let member = Self.makeMemberManifest(name: "app", dependencies: [])
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: Self.fileSystemDep(
                identity: "some-lib",
                relativePath: "external/some-lib",
            ),
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.isEmpty)
    }

    /// When a member manifest declares a `.fileSystem` dep whose identity
    /// matches an override, `apply(_:to:)` (member overload) substitutes
    /// the override's concrete kind but preserves the original member
    /// dep's `traits`. Trait preservation is the same invariant upheld by
    /// the workspace-level `apply(_:to:)` overload; this test proves the
    /// member overload upholds it too.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withSingleMatchingFileSystemDep_rewritesDepAndPreservesOriginalTraits() throws {
        let someTrait = PackageDependency.Trait(name: "some-trait")
        let originalDep = Self.fileSystemDep(
            identity: "some-lib",
            relativePath: "external/some-lib",
            traits: [someTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [originalDep],
        )
        let overridingDep = Self.fileSystemDep(
            identity: "some-lib",
            relativePath: "external/local-some-lib",
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 1)
        let rewritten = try #require(actual.dependencies.first)
        let settings = try #require(
            rewritten.fileSystemSettings,
            "expected .fileSystem dep, got \(rewritten)",
        )
        #expect(settings.path == AbsolutePath("/repo/external/local-some-lib"))
        #expect(rewritten.traits == [someTrait])
    }

    /// When a member manifest declares a `.sourceControl` dep whose
    /// identity matches an override that is ALSO `.sourceControl` (a
    /// URL + requirement redirect), `apply(_:to:)` substitutes the
    /// override's location and requirement but preserves the original
    /// member dep's `traits`. Pins the `.sourceControl` branch of the
    /// trait-preservation contract for the member overload.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withSingleMatchingSourceControlDep_rewritesDepAndPreservesOriginalTraits() throws {
        let someTrait = PackageDependency.Trait(name: "some-trait")
        let originalDep = Self.sourceControlDep(
            identity: "some-lib",
            url: "https://original.example.com/some-lib",
            minimumVersion: Version(1, 0, 0),
            traits: [someTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [originalDep],
        )
        let overridingDep = Self.sourceControlDep(
            identity: "some-lib",
            url: "https://fork.example.com/some-lib",
            minimumVersion: Version(2, 0, 0),
            traits: nil,
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 1)
        let rewritten = try #require(actual.dependencies.first)
        let settings = try #require(
            rewritten.sourceControlSettings,
            "expected .sourceControl dep, got \(rewritten)",
        )
        #expect(settings.location == .remote(SourceControlURL("https://fork.example.com/some-lib")))
        #expect(settings.requirement == .range(Version(2, 0, 0) ..< Version(3, 0, 0)))
        #expect(rewritten.traits == [someTrait])
    }

    /// A member's `.sourceControl` dep can be redirected to a local
    /// `.fileSystem` path via an override (the "URL dep swapped to a
    /// local checkout" scenario). `apply(_:to:)` substitutes the kind
    /// end-to-end while preserving the original member dep's `traits`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withSingleMatchingSourceControlDep_rewritesDepToFileSystemAndPreservesOriginalTraits() throws {
        let someTrait = PackageDependency.Trait(name: "some-trait")
        let originalDep = Self.sourceControlDep(
            identity: "some-lib",
            url: "https://original.example.com/some-lib",
            minimumVersion: Version(1, 0, 0),
            traits: [someTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [originalDep],
        )
        let overridingDep = Self.fileSystemDep(
            identity: "some-lib",
            relativePath: "external/local-some-lib",
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 1)
        let rewritten = try #require(actual.dependencies.first)
        let settings = try #require(
            rewritten.fileSystemSettings,
            "expected .fileSystem dep, got \(rewritten)",
        )
        #expect(settings.path == AbsolutePath("/repo/external/local-some-lib"))
        #expect(rewritten.traits == [someTrait])
    }

    /// When a member manifest declares a `.registry` dep whose identity
    /// matches an override that is ALSO `.registry` (a requirement
    /// bump), `apply(_:to:)` substitutes the override's requirement but
    /// preserves the original member dep's `traits`. Pins the
    /// `.registry` branch of the trait-preservation contract for the
    /// member overload.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withSingleMatchingRegistryDep_rewritesDepAndPreservesOriginalTraits() throws {
        let someTrait = PackageDependency.Trait(name: "some-trait")
        let originalDep = Self.registryDep(
            identity: "scope.lib",
            versionRange: Version(1, 0, 0) ..< Version(2, 0, 0),
            traits: [someTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [originalDep],
        )
        let overridingDep = Self.registryDep(
            identity: "scope.lib",
            versionRange: Version(2, 0, 0) ..< Version(3, 0, 0),
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("scope.lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 1)
        let rewritten = try #require(actual.dependencies.first)
        let settings = try #require(
            rewritten.registrySettings,
            "expected .registry dep, got \(rewritten)",
        )
        #expect(settings.requirement == .range(Version(2, 0, 0) ..< Version(3, 0, 0)))
        #expect(rewritten.traits == [someTrait])
    }

    /// A member's `.registry` dep can be redirected to a local
    /// `.fileSystem` path via an override (the "registry package
    /// swapped to a local dev checkout" scenario). `apply(_:to:)`
    /// substitutes the kind end-to-end while preserving the original
    /// member dep's `traits`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withSingleMatchingRegistryDep_rewritesDepToFileSystemAndPreservesOriginalTraits() throws {
        let someTrait = PackageDependency.Trait(name: "some-trait")
        let originalDep = Self.registryDep(
            identity: "scope.lib",
            versionRange: Version(1, 0, 0) ..< Version(2, 0, 0),
            traits: [someTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [originalDep],
        )
        let overridingDep = Self.fileSystemDep(
            identity: "scope.lib",
            relativePath: "external/local-scope-lib",
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("scope.lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 1)
        let rewritten = try #require(actual.dependencies.first)
        let settings = try #require(
            rewritten.fileSystemSettings,
            "expected .fileSystem dep, got \(rewritten)",
        )
        #expect(settings.path == AbsolutePath("/repo/external/local-scope-lib"))
        #expect(rewritten.traits == [someTrait])
    }

    /// Verifies that apply rewrites the matching dep at each position
    /// (head, middle, tail) and leaves all other deps — including their
    /// traits — byte-identical to the originals.
    struct PositionalCase: CustomTestStringConvertible {
        let label: String
        let matchIndex: Int
        var testDescription: String { label }
    }

    struct ValidateCase: CustomTestStringConvertible {
        let label: String
        let overrideIdentity: String
        let workspaceDepIdentity: String
        let memberDepIdentity: String
        var testDescription: String { label }
    }

    @Test(
        "apply rewrites the matching dep at each position and leaves other deps and their traits untouched",
        .tags(
            Tag.TestSize.small,
        ),
        arguments: [
            PositionalCase(label: "head",   matchIndex: 0),
            PositionalCase(label: "middle", matchIndex: 1),
            PositionalCase(label: "tail",   matchIndex: 2),
        ],
    )
    func apply_toMember_withMultipleDeps_rewritesMatchingDepAtPositionAndLeavesOthers(
        _ testCase: PositionalCase,
    ) throws {
        let originalTrait = PackageDependency.Trait(name: "original-trait")
        let bystanderTrait = PackageDependency.Trait(name: "bystander-trait")

        let identities = ["head-lib", "middle-lib", "tail-lib"]
        func traitsFor(index: Int) -> Set<PackageDependency.Trait> {
            index == testCase.matchIndex ? [originalTrait] : [bystanderTrait]
        }

        let originalHead = Self.fileSystemDep(
            identity: identities[0],
            relativePath: "external/\(identities[0])",
            traits: traitsFor(index: 0),
        )
        let originalMiddle = Self.fileSystemDep(
            identity: identities[1],
            relativePath: "external/\(identities[1])",
            traits: traitsFor(index: 1),
        )
        let originalTail = Self.sourceControlDep(
            identity: identities[2],
            url: "https://example.com/\(identities[2])",
            minimumVersion: Version(1, 0, 0),
            traits: traitsFor(index: 2),
        )
        let originals = [originalHead, originalMiddle, originalTail]
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: originals,
        )
        let targetIdentity = identities[testCase.matchIndex]
        let overridingDep = Self.fileSystemDep(
            identity: targetIdentity,
            relativePath: "external/local-\(targetIdentity)",
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain(targetIdentity),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 3)
        let rewritten = actual.dependencies[testCase.matchIndex]
        let settings = try #require(
            rewritten.fileSystemSettings,
            "expected .fileSystem dep at index \(testCase.matchIndex), got \(rewritten)",
        )
        #expect(settings.path == AbsolutePath("/repo/external/local-\(targetIdentity)"))
        #expect(actual.dependencies[testCase.matchIndex].traits == [originalTrait])
        for otherIndex in [0, 1, 2] where otherIndex != testCase.matchIndex {
            #expect(actual.dependencies[otherIndex] == originals[otherIndex])
        }
    }

    /// Exercises simultaneous multi-match: two overrides target head and
    /// tail while middle is left alone. The middle dep carries non-nil
    /// `bystanderTrait` to prove traits on non-matching entries pass through
    /// untouched. Confirms the `.map`-based rewrite scales past a single hit.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withMultipleDepsAndMultipleMatches_rewritesAllMatchesAndLeavesOthers() async throws {
        let originalTrait = PackageDependency.Trait(name: "original-trait")
        let bystanderTrait = PackageDependency.Trait(name: "bystander-trait")
        let originalHead = Self.fileSystemDep(
            identity: "head-lib",
            relativePath: "external/head-lib",
            traits: [originalTrait],
        )
        let originalMiddle = Self.fileSystemDep(
            identity: "middle-lib",
            relativePath: "external/middle-lib",
            traits: [bystanderTrait],
        )
        let originalTail = Self.sourceControlDep(
            identity: "tail-lib",
            url: "https://example.com/tail-lib",
            minimumVersion: Version(1, 0, 0),
            traits: [originalTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [originalHead, originalMiddle, originalTail],
        )
        let headOverridingDep = Self.fileSystemDep(
            identity: "head-lib",
            relativePath: "external/local-head-lib",
        )
        let tailOverridingDep = Self.fileSystemDep(
            identity: "tail-lib",
            relativePath: "external/local-tail-lib",
        )
        let overrides = [
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("head-lib"),
                overridingDependency: headOverridingDep,
            ),
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("tail-lib"),
                overridingDependency: tailOverridingDep,
            ),
        ]

        let actual = WorkspaceOverridesJSONParser.apply(overrides, to: member)

        #expect(actual.dependencies.count == 3)
        let rewrittenHead = actual.dependencies[0]
        let headSettings = try #require(
            rewrittenHead.fileSystemSettings,
            "expected .fileSystem dep at index 0, got \(rewrittenHead)",
        )
        #expect(headSettings.path == AbsolutePath("/repo/external/local-head-lib"))
        #expect(actual.dependencies[0].traits == [originalTrait])
        #expect(actual.dependencies[1] == originalMiddle)
        let rewrittenTail = actual.dependencies[2]
        let tailSettings = try #require(
            rewrittenTail.fileSystemSettings,
            "expected .fileSystem dep at index 2, got \(rewrittenTail)",
        )
        #expect(tailSettings.path == AbsolutePath("/repo/external/local-tail-lib"))
        #expect(actual.dependencies[2].traits == [originalTrait])
    }

    /// A `.workspaceInherited` dep declared in a member manifest is the
    /// mechanism by which the workspace injects a shared dep into the
    /// member. Even if its identity matches an override, `apply(_:to:)`
    /// (member overload) must leave the inherited dep in place — the
    /// inheritance-level override happens at the workspace-manifest layer,
    /// not the member layer. Substituting here would double-override.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withMatchingWorkspaceInheritedDep_leavesDepUnchanged() throws {
        let inheritedTrait = PackageDependency.Trait(name: "inherited-trait")
        let inheritedDep = Self.workspaceInheritedDep(
            identity: "shared-lib",
            traits: [inheritedTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [inheritedDep],
        )
        let overridingDep = Self.fileSystemDep(
            identity: "shared-lib",
            relativePath: "external/local-shared-lib",
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("shared-lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: member)

        #expect(actual.dependencies.count == 1)
        let dep = try #require(actual.dependencies.first)
        try expectWorkspaceInherited(
            dep,
            identity: .plain("shared-lib"),
            traits: [inheritedTrait],
        )
    }

    /// Mixed member manifest: a `.fileSystem` dep and a `.workspaceInherited`
    /// dep, with overrides targeting both identities. `apply(_:to:)` must
    /// rewrite the concrete `.fileSystem` dep AND leave the
    /// `.workspaceInherited` dep untouched — proving the skip is per-dep,
    /// not per-manifest.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_toMember_withMatchingConcreteAndWorkspaceInheritedDeps_rewritesOnlyConcrete() throws {
        let concreteTrait = PackageDependency.Trait(name: "concrete-trait")
        let inheritedTrait = PackageDependency.Trait(name: "inherited-trait")
        let concreteDep = Self.fileSystemDep(
            identity: "concrete-lib",
            relativePath: "external/concrete-lib",
            traits: [concreteTrait],
        )
        let inheritedDep = Self.workspaceInheritedDep(
            identity: "shared-lib",
            traits: [inheritedTrait],
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [concreteDep, inheritedDep],
        )
        let concreteOverride = WorkspaceOverridesJSONParser.Override(
            identity: .plain("concrete-lib"),
            overridingDependency: Self.fileSystemDep(
                identity: "concrete-lib",
                relativePath: "external/local-concrete-lib",
            ),
        )
        let inheritedOverride = WorkspaceOverridesJSONParser.Override(
            identity: .plain("shared-lib"),
            overridingDependency: Self.fileSystemDep(
                identity: "shared-lib",
                relativePath: "external/local-shared-lib",
            ),
        )

        let actual = WorkspaceOverridesJSONParser.apply(
            [concreteOverride, inheritedOverride],
            to: member,
        )

        #expect(actual.dependencies.count == 2)
        let rewrittenConcrete = try #require(
            actual.dependencies[0].fileSystemSettings,
            "expected .fileSystem at index 0, got \(actual.dependencies[0])",
        )
        #expect(rewrittenConcrete.path == AbsolutePath("/repo/external/local-concrete-lib"))
        #expect(actual.dependencies[0].traits == [concreteTrait])
        try expectWorkspaceInherited(
            actual.dependencies[1],
            identity: .plain("shared-lib"),
            traits: [inheritedTrait],
        )
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
    func apply_withSingleMatch_replacesDep() {
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

        let actual = WorkspaceOverridesJSONParser.apply([override], to: manifest)

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
    func apply_withMultipleMatches_replacesAll() {
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

        let actual = WorkspaceOverridesJSONParser.apply(overrides, to: manifest)

        #expect(actual.dependencies == [someReplacement, otherReplacement])
    }

    /// An override whose identity doesn't match any workspace-level
    /// dep is silently ignored — `apply(_:to:)` is a pure rewrite and
    /// never throws. Intentional design: the responsibility for
    /// rejecting unknown identities is delegated to
    /// `validate(_:workspaceManifest:memberManifests:)`, which throws
    /// `WorkspaceOverridesApplyError.unknownIdentity` after all
    /// manifests are loaded. This test pins the no-throw contract so
    /// a future refactor that accidentally re-introduces a throw here
    /// will surface immediately.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_withUnknownIdentity_returnsManifestUnchanged() {
        let manifest = Self.makeManifest(
            dependencies: [
                Self.fileSystemDep(identity: "some-lib", relativePath: "external/some-lib"),
            ],
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("ghost-lib"),
            overridingDependency: Self.fileSystemDep(identity: "ghost-lib", relativePath: "external/ghost"),
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: manifest)

        #expect(actual.dependencies == manifest.dependencies)
    }

    /// When `apply` substitutes a workspace-level dep it must carry the
    /// original dep's `traits` forward onto the replacement. The overriding
    /// dep is a local checkout (traits: nil); without preservation the
    /// traits would be silently dropped, changing resolver behaviour.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func apply_withMatchingIdentityAndOriginalTraits_preservesOriginalTraitsOnSubstitutedDep() throws {
        let someTrait = PackageDependency.Trait(name: "some-trait")
        let originalDep = Self.sourceControlDep(
            identity: "some-lib",
            url: "https://example.com/some-lib",
            minimumVersion: Version(2, 0, 0),
            traits: [someTrait],
        )
        let unchangedDep = Self.fileSystemDep(
            identity: "other-lib",
            relativePath: "external/other-lib",
        )
        let manifest = Self.makeManifest(
            dependencies: [originalDep, unchangedDep],
        )
        let overridingDep = Self.fileSystemDep(
            identity: "some-lib",
            relativePath: "external/local-some-lib",
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: overridingDep,
        )

        let actual = WorkspaceOverridesJSONParser.apply([override], to: manifest)

        #expect(actual.dependencies.count == 2)
        let substituted = try #require(actual.dependencies.first)
        #expect(substituted.traits == [someTrait])
        #expect(actual.dependencies[1] == unchangedDep)
    }

    // MARK: - validate

    /// `validate` accepts an override whose identity is declared in
    /// either the workspace manifest or in any member manifest.
    /// Presence at either scope is sufficient — the function need not
    /// find the identity in BOTH.
    @Test(
        "validate does not throw when override identity is known to either workspace or member scope",
        .tags(
            Tag.TestSize.small,
        ),
        arguments: [
            ValidateCase(
                label: "workspace scope only",
                overrideIdentity: "some-lib",
                workspaceDepIdentity: "some-lib",
                memberDepIdentity: "other-lib",
            ),
            ValidateCase(
                label: "member scope only",
                overrideIdentity: "member-lib",
                workspaceDepIdentity: "workspace-lib",
                memberDepIdentity: "member-lib",
            ),
        ],
    )
    func validate_withIdentityKnownToEitherScope_doesNotThrow(
        _ testCase: ValidateCase,
    ) throws {
        let workspaceManifest = Self.makeManifest(
            dependencies: [
                Self.fileSystemDep(
                    identity: testCase.workspaceDepIdentity,
                    relativePath: "external/\(testCase.workspaceDepIdentity)",
                ),
            ],
        )
        let memberManifest = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.fileSystemDep(
                    identity: testCase.memberDepIdentity,
                    relativePath: "external/\(testCase.memberDepIdentity)",
                ),
            ],
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain(testCase.overrideIdentity),
            overridingDependency: Self.fileSystemDep(
                identity: testCase.overrideIdentity,
                relativePath: "external/local-\(testCase.overrideIdentity)",
            ),
        )

        try WorkspaceOverridesJSONParser.validate(
            [override],
            workspaceManifest: workspaceManifest,
            memberManifests: [memberManifest],
        )
    }

    /// When an override's identity is not found in `workspaceManifest.dependencies`
    /// OR in any `memberManifest.dependencies`, `validate` throws
    /// `WorkspaceOverridesApplyError.unknownIdentity` carrying the identity
    /// string. This is the hard error that prevents silent mis-configuration —
    /// the override file references something that doesn't exist in the
    /// dependency graph at any scope.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func validate_withIdentityAbsentFromBothScopes_throwsUnknownIdentity() throws {
        let workspaceManifest = Self.makeManifest(
            dependencies: [
                Self.fileSystemDep(identity: "workspace-lib", relativePath: "external/workspace-lib"),
            ],
        )
        let memberManifest = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.fileSystemDep(identity: "member-lib", relativePath: "external/member-lib"),
            ],
        )
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("ghost-lib"),
            overridingDependency: Self.fileSystemDep(
                identity: "ghost-lib",
                relativePath: "external/ghost",
            ),
        )

        #expect(throws: WorkspaceOverridesApplyError.unknownIdentity("ghost-lib")) {
            try WorkspaceOverridesJSONParser.validate(
                [override],
                workspaceManifest: workspaceManifest,
                memberManifests: [memberManifest],
            )
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

    private func expectWorkspaceInherited(
        _ dep: PackageDependency,
        identity: PackageIdentity,
        traits: Set<PackageDependency.Trait>?,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let settings = try #require(
            dep.workspaceInheritedSettings,
            "expected .workspaceInherited dep, got \(dep)",
            sourceLocation: sourceLocation,
        )
        #expect(settings.identity == identity, sourceLocation: sourceLocation)
        #expect(dep.traits == traits, sourceLocation: sourceLocation)
    }

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

    private static func makeMemberManifest(
        name: String,
        dependencies: [PackageDependency],
    ) -> Manifest {
        let manifestPath = AbsolutePath("/repo/packages/\(name)/Package.swift")
        return Manifest(
            displayName: name,
            packageIdentity: PackageIdentity.plain(name),
            path: manifestPath,
            packageKind: .root(manifestPath.parentDirectory),
            packageLocation: manifestPath.parentDirectory.pathString,
            defaultLocalization: nil,
            platforms: [],
            version: nil,
            revision: nil,
            toolsVersion: .vNext,
            pkgConfig: nil,
            providers: nil,
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil,
            dependencies: dependencies,
            products: [],
            targets: [],
            traits: [],
        )
    }

    private static func fileSystemDep(
        identity: String,
        relativePath: String,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .fileSystem(
            identity: .plain(identity),
            nameForTargetDependencyResolutionOnly: nil,
            path: AbsolutePath("/repo").appending(try! RelativePath(validating: relativePath)),
            productFilter: .everything,
            traits: traits,
        )
    }

    private static func sourceControlDep(
        identity: String,
        url: String,
        minimumVersion: Version,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .sourceControl(
            identity: .plain(identity),
            nameForTargetDependencyResolutionOnly: nil,
            location: .remote(SourceControlURL(url)),
            requirement: .range(minimumVersion ..< Version(minimumVersion.major + 1, 0, 0)),
            productFilter: .everything,
            traits: traits,
            registryIdentity: nil,
        )
    }

    private static func registryDep(
        identity: String,
        versionRange: Range<Version>,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .registry(
            identity: .plain(identity),
            requirement: .range(versionRange),
            productFilter: .everything,
            traits: traits,
        )
    }

    private static func workspaceInheritedDep(
        identity: String,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: .plain(identity),
                productFilter: .everything,
                traits: traits,
            )
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
