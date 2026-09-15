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

@_spi(SwiftPMInternal) @testable import Commands
import Basics
import Testing
import _InternalTestSupport

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceManifestSyntaxTests {
    /// A bare `Workspace(...)` call with `members: []` yields an empty
    /// list. Locks in the "empty members" happy path — this is the
    /// shape emitted by `swift workspace init` when no
    /// `--members` are supplied.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readMembers_emptyArray_returnsEmpty() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
            dependencies: [],
        )
        """

        let members = try WorkspaceManifestSyntax.readMembers(from: source)

        #expect(members == [])
    }

    /// A single string-literal member is returned verbatim. Establishes
    /// the read contract: source-level `"packages/lib-a"` → list item
    /// `"packages/lib-a"` (no path normalization, no unwrapping).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readMembers_singleMember_returnsIt() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
            ],
        )
        """

        let members = try WorkspaceManifestSyntax.readMembers(from: source)

        #expect(members == ["packages/lib-a"])
    }

    /// Members are returned sorted alphabetically regardless of the
    /// order they appear in the source. This matches
    /// `swift workspace override list`, keeping list output
    /// deterministic across manifests that declare members in
    /// different orders.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readMembers_multipleMembers_returnsSortedAlphabetically() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
                "packages/app",
                "packages/lib-b",
            ],
        )
        """

        let members = try WorkspaceManifestSyntax.readMembers(from: source)

        #expect(members == ["packages/app", "packages/lib-a", "packages/lib-b"])
    }

    /// When the source has no `Workspace(...)` call, reading throws.
    /// This is the "not a workspace manifest" signal — callers must
    /// distinguish this from an empty-members workspace.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readMembers_noWorkspaceCall_throws() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let package = Package(name: "foo")
        """

        #expect(throws: (any Error).self) {
            try WorkspaceManifestSyntax.readMembers(from: source)
        }
    }

    // MARK: - addMember

    /// Adding a member to an empty `members: []` list produces a
    /// source where the new member is the sole entry — verified via
    /// `readMembers` round-trip so the test is decoupled from
    /// formatting choices (whitespace, trailing commas, comments).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addMember_toEmptyList_appendsNewMember() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
            dependencies: [],
        )
        """

        let edited = try WorkspaceManifestSyntax.addMember("packages/lib-a", to: source)

        let members = try WorkspaceManifestSyntax.readMembers(from: edited)
        #expect(members == ["packages/lib-a"])
    }

    /// Adding a member to a non-empty list appends to the existing set
    /// and preserves every prior entry — verified via `readMembers`
    /// round-trip.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addMember_toNonEmptyList_appendsAlongsideExisting() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
            ],
        )
        """

        let edited = try WorkspaceManifestSyntax.addMember("packages/app", to: source)

        let members = try WorkspaceManifestSyntax.readMembers(from: edited)
        #expect(members == ["packages/app", "packages/lib-a"])
    }

    /// Adding a member that already exists is a no-op — the returned
    /// source is byte-identical to the input. Locks in idempotency so
    /// `swift workspace add-member` can be re-run safely
    /// without producing spurious diffs.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addMember_whenDuplicate_returnsUnchangedSource() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
            ],
        )
        """

        let edited = try WorkspaceManifestSyntax.addMember("packages/lib-a", to: source)

        #expect(edited == source)
    }

    /// Adding a member to a source without a `Workspace(...)` call
    /// throws — the CLI callers use this to distinguish "not a
    /// workspace manifest" from "manifest exists but has no members".
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addMember_whenNoWorkspaceCall_throws() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let package = Package(name: "foo")
        """

        #expect(throws: (any Error).self) {
            try WorkspaceManifestSyntax.addMember("packages/lib-a", to: source)
        }
    }

    // MARK: - removeMember

    /// Removing an existing member drops it from the list; the
    /// remaining entries are preserved. Verified via `readMembers`
    /// round-trip so the assertion is decoupled from formatting.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func removeMember_whenPresent_dropsEntry() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
                "packages/app",
            ],
        )
        """

        let edited = try WorkspaceManifestSyntax.removeMember("packages/lib-a", from: source)

        let members = try WorkspaceManifestSyntax.readMembers(from: edited)
        #expect(members == ["packages/app"])
    }

    /// Removing the last member leaves an empty `members: []` list.
    /// The workspace manifest stays syntactically valid so subsequent
    /// tooling (or a re-run of `add-member`) still works.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func removeMember_whenLastEntry_leavesEmptyList() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
            ],
        )
        """

        let edited = try WorkspaceManifestSyntax.removeMember("packages/lib-a", from: source)

        let members = try WorkspaceManifestSyntax.readMembers(from: edited)
        #expect(members == [])
    }

    /// Removing a member that isn't present throws — mirrors the
    /// `swift workspace override remove <identity>` behaviour
    /// so mistyped paths surface early rather than silently no-op.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func removeMember_whenAbsent_throws() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/lib-a",
            ],
        )
        """

        #expect(throws: (any Error).self) {
            try WorkspaceManifestSyntax.removeMember("packages/ghost", from: source)
        }
    }

    /// Removing from a source without a `Workspace(...)` call throws
    /// the same `.cannotFindWorkspaceCall` used by the read/add
    /// entrypoints — callers can dispatch on the error kind uniformly.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func removeMember_whenNoWorkspaceCall_throws() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let package = Package(name: "foo")
        """

        #expect(throws: (any Error).self) {
            try WorkspaceManifestSyntax.removeMember("packages/lib-a", from: source)
        }
    }

    // MARK: - AddMember.shouldScaffoldMemberPackage
    /// pre-flight decision returns `true` and emits nothing — the
    /// scaffold path runs.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func shouldScaffoldMemberPackage_whenManifestMissing_returnsTrueAndEmitsNothing() throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()
        let memberManifest = AbsolutePath("/repo/packages/lib-b/Package.swift")

        let shouldScaffold = SwiftWorkspaceCommand.AddMember.shouldScaffoldMemberPackage(
            memberPath: "packages/lib-b",
            memberManifest: memberManifest,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope,
        )

        #expect(shouldScaffold)
        #expect(observability.diagnostics.isEmpty)
    }

    /// When the target member manifest already exists, the pre-flight
    /// decision returns `false` and emits
    /// `.scaffoldIgnoredMemberAlreadyExists` — matches the CLI
    /// warning-not-error framing. Verified by comparing severity +
    /// message against a freshly-constructed diagnostic to lock in
    /// both the decision and the exact emission shape.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func shouldScaffoldMemberPackage_whenManifestExists_returnsFalseAndEmitsWarning() throws {
        let fileSystem = InMemoryFileSystem()
        let memberDir = AbsolutePath("/repo/packages/lib-a")
        try fileSystem.createDirectory(memberDir, recursive: true)
        let memberManifest = memberDir.appending("Package.swift")
        try fileSystem.writeFileContents(memberManifest, string: "// pre-existing\n")
        let observability = ObservabilitySystem.makeForTesting()

        let shouldScaffold = SwiftWorkspaceCommand.AddMember.shouldScaffoldMemberPackage(
            memberPath: "packages/lib-a",
            memberManifest: memberManifest,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope,
        )

        #expect(shouldScaffold == false)
        let expected = Basics.Diagnostic.scaffoldIgnoredMemberAlreadyExists(
            memberPath: "packages/lib-a",
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    // MARK: - readDependencies

    /// A workspace manifest with an explicit empty `dependencies: []`
    /// yields an empty list. Regression guard against the read helper
    /// misinterpreting an empty literal as "no `dependencies:`
    /// argument".
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readDependencies_emptyArray_returnsEmpty() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
            dependencies: [],
        )
        """

        let dependencies = try WorkspaceManifestSyntax.readDependencies(from: source)

        #expect(dependencies == [])
    }

    /// A workspace manifest that omits the `dependencies:` argument
    /// entirely also yields an empty list — `dependencies:` is optional
    /// on `Workspace(...)`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readDependencies_missingArg_returnsEmpty() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
        )
        """

        let dependencies = try WorkspaceManifestSyntax.readDependencies(from: source)

        #expect(dependencies == [])
    }

    /// A single `.package(url:from:)` entry round-trips through the
    /// read helper as its source-level `trimmedDescription`. Callers
    /// use this to detect "already present" for idempotency without
    /// re-parsing the requirement.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func readDependencies_urlDependency_returnsIt() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
            dependencies: [
                .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
            ],
        )
        """

        let dependencies = try WorkspaceManifestSyntax.readDependencies(from: source)

        #expect(dependencies.count == 1)
        let entry = try #require(dependencies.first)
        #expect(entry.contains("swift-nio"))
        #expect(entry.contains("2.0.0"))
    }

    // MARK: - addDependency

    /// Adding a dependency to a workspace whose `Workspace(...)` call
    /// has no `dependencies:` argument at all inserts one and populates
    /// it with the new entry. `readDependencies` sees the added entry
    /// after the edit — the assertion is decoupled from formatting.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addDependency_toManifestWithNoDependenciesArg_addsDependenciesArg() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [
                "packages/app",
            ],
        )
        """

        let edited = try WorkspaceManifestSyntax.addDependency(
            #".package(url: "https://github.com/apple/swift-nio", from: "2.0.0")"#,
            to: source,
        )

        let dependencies = try WorkspaceManifestSyntax.readDependencies(from: edited)
        #expect(dependencies.count == 1)
        let entry = try #require(dependencies.first)
        #expect(entry.contains("swift-nio"))
        #expect(entry.contains("2.0.0"))
    }

    /// Adding a dependency to a workspace whose `dependencies:` is
    /// present-but-empty appends the entry as the sole element.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addDependency_toEmptyDependenciesArray_appendsSingleEntry() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
            dependencies: [],
        )
        """

        let edited = try WorkspaceManifestSyntax.addDependency(
            #".package(url: "https://github.com/apple/swift-log", from: "1.0.0")"#,
            to: source,
        )

        let dependencies = try WorkspaceManifestSyntax.readDependencies(from: edited)
        #expect(dependencies.count == 1)
        let entry = try #require(dependencies.first)
        #expect(entry.contains("swift-log"))
    }

    /// Adding a dependency to a workspace that already has one leaves
    /// the existing entry alone and appends the new one alongside.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addDependency_toNonEmptyDependenciesArray_appendsAlongsideExisting() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let workspace = Workspace(
            members: [],
            dependencies: [
                .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
            ],
        )
        """

        let edited = try WorkspaceManifestSyntax.addDependency(
            #".package(url: "https://github.com/apple/swift-log", from: "1.0.0")"#,
            to: source,
        )

        let dependencies = try WorkspaceManifestSyntax.readDependencies(from: edited)
        #expect(dependencies.count == 2)
        #expect(dependencies.contains(where: { $0.contains("swift-nio") }))
        #expect(dependencies.contains(where: { $0.contains("swift-log") }))
    }

    /// Adding a dependency to a source that has no `Workspace(...)`
    /// call at all throws — matches the readMembers/addMember/
    /// removeMember error surface so callers can dispatch uniformly.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func addDependency_whenNoWorkspaceCall_throws() throws {
        let source = """
        // swift-tools-version: 999.0
        import PackageDescription

        let package = Package(name: "foo")
        """

        #expect(throws: (any Error).self) {
            try WorkspaceManifestSyntax.addDependency(
                #".package(url: "https://github.com/apple/swift-nio", from: "2.0.0")"#,
                to: source,
            )
        }
    }
}
