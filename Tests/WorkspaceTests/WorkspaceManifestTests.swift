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
import PackageLoading
import PackageModel
import Testing
@_spi(SwiftPMInternal) import Workspace
import _InternalTestSupport

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceManifestTests {
    // MARK: - discoverWorkspaceRoot

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func discoverWorkspaceRoot_atRootDirectory_findsWorkspaceSwift() throws {
        let fileSystem = InMemoryFileSystem()
        let root = AbsolutePath("/repo")
        try fileSystem.createDirectory(root, recursive: true)
        try fileSystem.writeFileContents(root.appending("Workspace.swift"), string: "")

        let discovered = PackageWorkspace.discoverWorkspaceRoot(
            from: root,
            fileSystem: fileSystem,
        )

        #expect(discovered == root)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func discoverWorkspaceRoot_fromSubdirectory_walksUpToWorkspaceRoot() throws {
        let fileSystem = InMemoryFileSystem()
        let root = AbsolutePath("/repo")
        let member = root.appending(components: "packages", "lib-a")
        try fileSystem.createDirectory(member, recursive: true)
        try fileSystem.writeFileContents(root.appending("Workspace.swift"), string: "")

        let discovered = PackageWorkspace.discoverWorkspaceRoot(
            from: member,
            fileSystem: fileSystem,
        )

        #expect(discovered == root)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func discoverWorkspaceRoot_noWorkspaceSwiftInAncestors_returnsNil() throws {
        let fileSystem = InMemoryFileSystem()
        let dir = AbsolutePath("/no/workspace/here")
        try fileSystem.createDirectory(dir, recursive: true)

        let discovered = PackageWorkspace.discoverWorkspaceRoot(
            from: dir,
            fileSystem: fileSystem,
        )

        #expect(discovered == nil)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func discoverWorkspaceRoot_multipleAncestors_findsClosest() throws {
        let fileSystem = InMemoryFileSystem()
        let outer = AbsolutePath("/outer")
        let inner = outer.appending("inner")
        let deep = inner.appending(components: "some", "sub", "dir")
        try fileSystem.createDirectory(deep, recursive: true)
        try fileSystem.writeFileContents(outer.appending("Workspace.swift"), string: "")
        try fileSystem.writeFileContents(inner.appending("Workspace.swift"), string: "")

        let discovered = PackageWorkspace.discoverWorkspaceRoot(
            from: deep,
            fileSystem: fileSystem,
        )

        #expect(discovered == inner)
    }

    // MARK: - findEnclosingMember

    /// Convenience: build a `WorkspaceManifest.Member` at a fixed
    /// identity + path for the `findEnclosingMember` tests.
    private static func member(
        _ identity: String,
        at path: AbsolutePath,
    ) -> WorkspaceManifest.Member {
        WorkspaceManifest.Member(
            identity: PackageIdentity.plain(identity),
            path: path,
        )
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findEnclosingMember_whenCwdEqualsMemberPath_returnsThatIdentity() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending(components: "packages", "lib-a")
        let members = [Self.member("lib-a", at: memberPath)]

        let focus = PackageWorkspace.findEnclosingMember(
            cwd: memberPath,
            in: members,
        )

        #expect(focus == PackageIdentity.plain("lib-a"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findEnclosingMember_whenCwdDeepInsideMember_returnsThatIdentity() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending(components: "packages", "lib-a")
        let cwd = memberPath.appending(components: "Sources", "LibA", "sub")
        let members = [Self.member("lib-a", at: memberPath)]

        let focus = PackageWorkspace.findEnclosingMember(
            cwd: cwd,
            in: members,
        )

        #expect(focus == PackageIdentity.plain("lib-a"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findEnclosingMember_whenCwdAtWorkspaceRoot_returnsNil() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let members = [
            Self.member(
                "lib-a",
                at: workspaceRoot.appending(components: "packages", "lib-a"),
            ),
            Self.member(
                "lib-b",
                at: workspaceRoot.appending(components: "packages", "lib-b"),
            ),
        ]

        let focus = PackageWorkspace.findEnclosingMember(
            cwd: workspaceRoot,
            in: members,
        )

        #expect(focus == nil)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findEnclosingMember_whenCwdInUnrelatedSibling_returnsNil() throws {
        // CWD is in `external/some-lib`, which is not a workspace
        // member (it's a workspace-level dependency source).
        let workspaceRoot = AbsolutePath("/repo")
        let members = [
            Self.member(
                "lib-a",
                at: workspaceRoot.appending(components: "packages", "lib-a"),
            ),
        ]
        let cwd = workspaceRoot.appending(components: "external", "some-lib")

        let focus = PackageWorkspace.findEnclosingMember(
            cwd: cwd,
            in: members,
        )

        #expect(focus == nil)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findEnclosingMember_whenNestedMembers_returnsDeepestMatch() throws {
        // Pathological but valid: a member is nested inside another
        // member's directory. `findEnclosingMember` must select the
        // deepest matching member.
        let workspaceRoot = AbsolutePath("/repo")
        let outerPath = workspaceRoot.appending("outer")
        let innerPath = outerPath.appending(components: "nested", "inner")
        let members = [
            Self.member("outer", at: outerPath),
            Self.member("inner", at: innerPath),
        ]
        let cwd = innerPath.appending("Sources")

        let focus = PackageWorkspace.findEnclosingMember(
            cwd: cwd,
            in: members,
        )

        #expect(focus == PackageIdentity.plain("inner"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findEnclosingMember_whenMembersEmpty_returnsNil() throws {
        let focus = PackageWorkspace.findEnclosingMember(
            cwd: AbsolutePath("/repo/packages/anywhere"),
            in: [],
        )

        #expect(focus == nil)
    }

    // MARK: - WorkspaceManifestJSONParser

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withOneMember_yieldsResolvedMember() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")
        let expectedPath = workspaceRoot.appending(components: "packages", "lib-a")
        let expected = WorkspaceManifestJSONParser.Member(
            identity: PackageIdentity(path: expectedPath),
            path: expectedPath,
            ignoredStateDirectories: [],
        )

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.members.count == 1)
        #expect(result.members[0] == expected)
        #expect(result.dependencies.isEmpty)
    }

    /// A single `ignoredStateDirectories` string maps to the matching
    /// `WorkspaceManifest.StateDirectoryKind`. Locks in the wire-name
    /// → enum-case mapping for `.build` — a boundary the string-
    /// literal-based `Codable` enum silently depends on.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withMemberHavingBuildIgnoredKind_yieldsSetContainingBuild() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":["build"],"path":"packages/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")
        let expectedPath = workspaceRoot.appending(components: "packages", "lib-a")
        let expected = WorkspaceManifestJSONParser.Member(
            identity: PackageIdentity(path: expectedPath),
            path: expectedPath,
            ignoredStateDirectories: [.build],
        )

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.members.count == 1)
        #expect(result.members[0] == expected)
    }

    /// All four `StateDirectoryKind` cases round-trip through the
    /// wire format. If a new kind is added to the enum without a
    /// corresponding entry in `WorkspaceManifestJSONParser.mapKind`,
    /// this test won't fail — but it does pin the full mapping table
    /// against silent regressions on the existing four kinds.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withMemberHavingAllIgnoredKinds_yieldsSetWithAllKinds() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":["build","packageResolved","packages","swiftpmConfig"],"path":"packages/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")
        let expectedPath = workspaceRoot.appending(components: "packages", "lib-a")
        let expected = WorkspaceManifestJSONParser.Member(
            identity: PackageIdentity(path: expectedPath),
            path: expectedPath,
            ignoredStateDirectories: [.build, .packageResolved, .packages, .swiftpmConfig],
        )

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.members.count == 1)
        #expect(result.members[0] == expected)
    }

    /// Two members with different `ignoredStateDirectories` sets:
    /// each member's set is parsed independently. Guards against a
    /// bug where the parser accidentally shares or overwrites the set
    /// across members while iterating the wire array.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withTwoMembersHavingDistinctIgnoredKinds_parsesEachIndependently() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":["build"],"path":"packages/lib-a"},{"ignoredStateDirectories":["packageResolved","packages"],"path":"packages/lib-b"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")
        let libAPath = workspaceRoot.appending(components: "packages", "lib-a")
        let libBPath = workspaceRoot.appending(components: "packages", "lib-b")
        let expectedLibA = WorkspaceManifestJSONParser.Member(
            identity: PackageIdentity(path: libAPath),
            path: libAPath,
            ignoredStateDirectories: [.build],
        )
        let expectedLibB = WorkspaceManifestJSONParser.Member(
            identity: PackageIdentity(path: libBPath),
            path: libBPath,
            ignoredStateDirectories: [.packageResolved, .packages],
        )

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.members.count == 2)
        #expect(result.members[0] == expectedLibA)
        #expect(result.members[1] == expectedLibB)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withTwoMembers_yieldsBothWithDistinctIdentities() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"},{"ignoredStateDirectories":[],"path":"packages/lib-b"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.members.count == 2)
        #expect(result.members[0].identity != result.members[1].identity)
        #expect(result.members[0].path == workspaceRoot.appending(components: "packages", "lib-a"))
        #expect(result.members[1].path == workspaceRoot.appending(components: "packages", "lib-b"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withEmptyMembers_throws() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        #expect(throws: WorkspaceManifestParseError.emptyMembers) {
            try WorkspaceManifestJSONParser.parse(
                v2: json,
                workspaceRoot: workspaceRoot,
            )
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withAbsoluteMemberPath_throws() throws {
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":[],"path":"/absolute/path"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        #expect(throws: WorkspaceManifestParseError.memberAbsolutePathError(memberName: "path", path: "/absolute/path")) {
            try WorkspaceManifestJSONParser.parse(
                v2: json,
                workspaceRoot: workspaceRoot,
            )
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withDuplicateMemberIdentities_throws() throws {
        // Both paths resolve to identity "lib-a" (last path component).
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[],"members":[{"ignoredStateDirectories":[],"path":"frontend/lib-a"},{"ignoredStateDirectories":[],"path":"backend/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        #expect(throws: WorkspaceManifestParseError.duplicateMembernames(name: "lib-a")) {
            try WorkspaceManifestJSONParser.parse(
                v2: json,
                workspaceRoot: workspaceRoot,
            )
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withOneFileSystemDependency_yieldsResolvedDependency() throws {
        // Workspace declares a single .fileSystem dependency pointing to
        // `external/some-lib` (relative to the workspace root). The parser
        // should populate `result.dependencies` with a model
        // PackageDependency of the corresponding kind, with the path
        // resolved to an absolute path anchored at the workspace root.
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[{"kind":{"fileSystem":{"name":null,"path":"external/some-lib"}},"moduleAliases":null,"traits":null}],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.dependencies.count == 1)
        guard case .fileSystem(let fs) = result.dependencies[0] else {
            Issue.record("expected .fileSystem, got: \(result.dependencies[0])")
            return
        }
        #expect(fs.path == workspaceRoot.appending(components: "external", "some-lib"))
        #expect(fs.identity == PackageIdentity(path: fs.path))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withOneSourceControlDependency_yieldsResolvedDependency() throws {
        // Workspace declares a single .sourceControl dep pointing to a
        // remote git URL with a version range [2.0.0, 3.0.0).
        let version200 = #"{"buildMetadataIdentifiers":[],"major":2,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let version300 = #"{"buildMetadataIdentifiers":[],"major":3,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let requirement = #"{"range":{"lowerBound":\#(version200),"upperBound":\#(version300)}}"#
        let scDep = #"{"kind":{"sourceControl":{"location":"https://github.com/apple/swift-nio","name":null,"requirement":\#(requirement)}},"moduleAliases":null,"traits":null}"#
        let json = #"{"errors":[],"version":2,"workspace":{"dependencies":[\#(scDep)],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}"#
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.dependencies.count == 1)
        guard case .sourceControl(let sc) = result.dependencies[0] else {
            Issue.record("expected .sourceControl, got: \(result.dependencies[0])")
            return
        }
        #expect(sc.identity.description == "swift-nio")
        if case .remote(let url) = sc.location {
            #expect(url.absoluteString == "https://github.com/apple/swift-nio")
        } else {
            Issue.record("expected .remote location, got: \(sc.location)")
        }
        if case .range(let range) = sc.requirement {
            #expect(range.lowerBound.description == "2.0.0")
            #expect(range.upperBound.description == "3.0.0")
        } else {
            Issue.record("expected .range requirement, got: \(sc.requirement)")
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withOneRegistryDependency_yieldsResolvedDependency() throws {
        // Workspace declares a registry dep with a version range.
        let version100 = #"{"buildMetadataIdentifiers":[],"major":1,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let version200 = #"{"buildMetadataIdentifiers":[],"major":2,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let requirement = #"{"range":{"lowerBound":\#(version100),"upperBound":\#(version200)}}"#
        let regDep = #"{"kind":{"registry":{"id":"scope.pkg","requirement":\#(requirement)}},"moduleAliases":null,"traits":null}"#
        let json = #"{"errors":[],"version":2,"workspace":{"dependencies":[\#(regDep)],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}"#
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.dependencies.count == 1)
        guard case .registry(let reg) = result.dependencies[0] else {
            Issue.record("expected .registry, got: \(result.dependencies[0])")
            return
        }
        #expect(reg.identity.description == "scope.pkg")
        if case .range(let range) = reg.requirement {
            #expect(range.lowerBound.description == "1.0.0")
            #expect(range.upperBound.description == "2.0.0")
        } else {
            Issue.record("expected .range requirement, got: \(reg.requirement)")
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withMultipleWorkspaceDependencies_yieldsAllInOrder() throws {
        // Workspace with three deps: fileSystem + sourceControl + registry.
        // Verifies the parser produces all three and preserves order.
        let fsDep = #"{"kind":{"fileSystem":{"name":null,"path":"external/some-lib"}},"moduleAliases":null,"traits":null}"#
        let version200 = #"{"buildMetadataIdentifiers":[],"major":2,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let version300 = #"{"buildMetadataIdentifiers":[],"major":3,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let scRequirement = #"{"range":{"lowerBound":\#(version200),"upperBound":\#(version300)}}"#
        let scDep = #"{"kind":{"sourceControl":{"location":"https://github.com/apple/swift-nio","name":null,"requirement":\#(scRequirement)}},"moduleAliases":null,"traits":null}"#
        let version100 = #"{"buildMetadataIdentifiers":[],"major":1,"minor":0,"patch":0,"prereleaseIdentifiers":[]}"#
        let regRequirement = #"{"range":{"lowerBound":\#(version100),"upperBound":\#(version200)}}"#
        let regDep = #"{"kind":{"registry":{"id":"scope.pkg","requirement":\#(regRequirement)}},"moduleAliases":null,"traits":null}"#
        let json = #"{"errors":[],"version":2,"workspace":{"dependencies":[\#(fsDep),\#(scDep),\#(regDep)],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}"#
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.dependencies.count == 3)
        guard case .fileSystem = result.dependencies[0] else {
            Issue.record("expected .fileSystem at index 0")
            return
        }
        guard case .sourceControl = result.dependencies[1] else {
            Issue.record("expected .sourceControl at index 1")
            return
        }
        guard case .registry = result.dependencies[2] else {
            Issue.record("expected .registry at index 2")
            return
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_withAbsolutePathFileSystemDependency_yieldsAbsolutePath() throws {
        // Workspace declares a .fileSystem dep with an absolute path.
        // The parser should recognize the absolute path and NOT anchor
        // it at the workspace root.
        let json = #"{"errors":[],"version":2,"workspace":{"dependencies":[{"kind":{"fileSystem":{"name":null,"path":"/absolute/external/some-lib"}},"moduleAliases":null,"traits":null}],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}"#
        let workspaceRoot = AbsolutePath("/repo")

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.dependencies.count == 1)
        guard case .fileSystem(let fs) = result.dependencies[0] else {
            Issue.record("expected .fileSystem")
            return
        }
        #expect(fs.path == AbsolutePath("/absolute/external/some-lib"))
        #expect(fs.identity == PackageIdentity(path: fs.path))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_workspaceDependenciesWithWorkspaceMember_throwsActionableError() throws {
        // Workspace.swift's own `dependencies:` list contains a
        // `.package(workspaceMember: "foo")` entry — invalid because
        // workspace-scoped kinds are member-level, not workspace-level.
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[{"kind":{"workspaceMember":{"identity":"foo"}},"moduleAliases":null,"traits":null}],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        var caughtError: Error?
        do {
            _ = try WorkspaceManifestJSONParser.parse(
                v2: json,
                workspaceRoot: workspaceRoot,
            )
        } catch {
            caughtError = error
        }

        guard let error = caughtError as? ManifestParseError,
              case .runtimeManifestErrors(let messages) = error
        else {
            Issue.record("expected ManifestParseError.runtimeManifestErrors, got: \(String(describing: caughtError))")
            return
        }
        try #require(messages.count == 1)
        let message = messages[0]
        // Message must identify: kind (workspaceMember), the offending
        // identity ("foo"), and suggest concrete alternatives.
        #expect(message.contains("workspaceMember"))
        #expect(message.contains("\"foo\""))
        #expect(message.contains(".package(path:)"))
        #expect(message.contains(".package(url:)"))
        #expect(message.contains(".package(id:)"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func parseJSON_workspaceDependenciesWithWorkspaceInherited_throwsActionableError() throws {
        // Workspace.swift's own `dependencies:` list contains a
        // `.package(workspaceInherited: "foo")` entry — invalid because
        // a workspace cannot inherit from itself.
        let json = """
        {"errors":[],"version":2,"workspace":{"dependencies":[{"kind":{"workspaceInherited":{"identity":"foo"}},"moduleAliases":null,"traits":null}],"members":[{"ignoredStateDirectories":[],"path":"packages/lib-a"}]}}
        """
        let workspaceRoot = AbsolutePath("/repo")

        var caughtError: Error?
        do {
            _ = try WorkspaceManifestJSONParser.parse(
                v2: json,
                workspaceRoot: workspaceRoot,
            )
        } catch {
            caughtError = error
        }

        guard let error = caughtError as? ManifestParseError,
              case .runtimeManifestErrors(let messages) = error
        else {
            Issue.record("expected ManifestParseError.runtimeManifestErrors, got: \(String(describing: caughtError))")
            return
        }
        try #require(messages.count == 1)
        let message = messages[0]
        #expect(message.contains("workspaceInherited"))
        #expect(message.contains("\"foo\""))
        #expect(message.contains(".package(path:)"))
        #expect(message.contains(".package(url:)"))
        #expect(message.contains(".package(id:)"))
    }

    // MARK: - ManifestLoader.loadWorkspaceManifest

    @Test(
        .tags(
            Tag.TestSize.medium,
        ),
    )
    func loadWorkspaceManifest_withTwoMembers_producesResolvedMembers() async throws {
        try await withTemporaryDirectory { tempDir in
            let workspaceRoot = tempDir.appending("workspace")
            try localFileSystem.createDirectory(workspaceRoot, recursive: true)

            let workspaceManifest = """
            // swift-tools-version: 999.0
            import PackageDescription

            let workspace = Workspace(
                members: [
                    "packages/lib-a",
                    "packages/lib-b",
                ],
            )
            """
            try localFileSystem.writeFileContents(
                workspaceRoot.appending(WorkspaceManifest.filename),
                string: workspaceManifest,
            )

            let manifestLoader = ManifestLoader(toolchain: try UserToolchain.default)
            let observability = ObservabilitySystem.makeForTesting()

            let result = try await manifestLoader.loadWorkspaceManifest(
                at: workspaceRoot.appending(WorkspaceManifest.filename),
                toolsVersion: .vNext,
                workspaceRoot: workspaceRoot,
                observabilityScope: observability.topScope,
            )

            try #require(result.members.count == 2)
            #expect(result.members[0].identity.description == "lib-a")
            #expect(result.members[1].identity.description == "lib-b")
            #expect(result.dependencies.isEmpty)
        }
    }

    // MARK: - PackageWorkspace.loadWorkspaceManifest

    @Test(
        .tags(
            Tag.TestSize.medium,
        ),
    )
    func packageWorkspaceLoadWorkspaceManifest_withValidWorkspace_yieldsResolvedManifest() async throws {
        try await withTemporaryDirectory { tempDir in
            let workspaceRoot = tempDir.appending("workspace")
            try Self.writeMinimalWorkspaceAndMembers(
                at: workspaceRoot,
                memberPaths: ["packages/lib-a", "packages/lib-b"],
            )

            let manifestLoader = ManifestLoader(toolchain: try UserToolchain.default)
            let observability = ObservabilitySystem.makeForTesting()

            let manifest = try await PackageWorkspace.loadWorkspaceManifest(
                at: workspaceRoot,
                manifestLoader: manifestLoader,
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope,
            )

            #expect(manifest.path == workspaceRoot.appending(WorkspaceManifest.filename))
            #expect(manifest.toolsVersion == .vNext)
            try #require(manifest.members.count == 2)
            #expect(manifest.members[0].identity.description == "lib-a")
            #expect(manifest.members[1].identity.description == "lib-b")
        }
    }

    @Test(
        .tags(
            Tag.TestSize.medium,
        ),
    )
    func packageWorkspaceLoadWorkspaceManifest_withMissingMemberDirectory_throws() async throws {
        try await withTemporaryDirectory { tempDir in
            let workspaceRoot = tempDir.appending("workspace")
            try localFileSystem.createDirectory(workspaceRoot, recursive: true)

            try localFileSystem.writeFileContents(
                workspaceRoot.appending(WorkspaceManifest.filename),
                string: """
                // swift-tools-version: 999.0
                import PackageDescription

                let workspace = Workspace(
                    members: [
                        "packages/does-not-exist",
                    ],
                )
                """,
            )

            let manifestLoader = ManifestLoader(toolchain: try UserToolchain.default)
            let observability = ObservabilitySystem.makeForTesting()

            await #expect(
                throws: WorkspaceManifestParseError.memberPathNotFound(
                    memberName: "does-not-exist",
                    path: workspaceRoot.appending(components: "packages", "does-not-exist").pathString,
                ),
            ) {
                try await PackageWorkspace.loadWorkspaceManifest(
                    at: workspaceRoot,
                    manifestLoader: manifestLoader,
                    fileSystem: localFileSystem,
                    observabilityScope: observability.topScope,
                )
            }
        }
    }

    @Test(
        .tags(
            Tag.TestSize.medium,
        ),
    )
    func packageWorkspaceLoadWorkspaceManifest_withMemberMissingPackageSwift_throws() async throws {
        try await withTemporaryDirectory { tempDir in
            let workspaceRoot = tempDir.appending("workspace")
            try localFileSystem.createDirectory(workspaceRoot, recursive: true)

            // Member directory exists but has no Package.swift.
            let orphan = workspaceRoot.appending(components: "packages", "orphan")
            try localFileSystem.createDirectory(orphan, recursive: true)

            try localFileSystem.writeFileContents(
                workspaceRoot.appending(WorkspaceManifest.filename),
                string: """
                // swift-tools-version: 999.0
                import PackageDescription

                let workspace = Workspace(
                    members: [
                        "packages/orphan",
                    ],
                )
                """,
            )

            let manifestLoader = ManifestLoader(toolchain: try UserToolchain.default)
            let observability = ObservabilitySystem.makeForTesting()

            await #expect(
                throws: WorkspaceManifestParseError.memberMissingPackageManifest(
                    memberName: "orphan",
                    path: orphan.pathString,
                ),
            ) {
                try await PackageWorkspace.loadWorkspaceManifest(
                    at: workspaceRoot,
                    manifestLoader: manifestLoader,
                    fileSystem: localFileSystem,
                    observabilityScope: observability.topScope,
                )
            }
        }
    }

    // MARK: - Helpers

    /// Writes a minimal Workspace.swift plus each member's Package.swift and
    /// a bare Sources directory. Used by medium tests that need a valid
    /// on-disk workspace layout.
    static func writeMinimalWorkspaceAndMembers(
        at workspaceRoot: AbsolutePath,
        memberPaths: [String],
    ) throws {
        try localFileSystem.createDirectory(workspaceRoot, recursive: true)

        let membersLiteral = memberPaths
            .map { "        \"\($0)\"," }
            .joined(separator: "\n")

        try localFileSystem.writeFileContents(
            workspaceRoot.appending(WorkspaceManifest.filename),
            string: """
            // swift-tools-version: 999.0
            import PackageDescription

            let workspace = Workspace(
                members: [
            \(membersLiteral)
                ],
            )
            """,
        )

        for memberPath in memberPaths {
            let relative = try RelativePath(validating: memberPath)
            let memberRoot = workspaceRoot.appending(relative)
            let name = memberRoot.basename
            try localFileSystem.createDirectory(memberRoot, recursive: true)
            try localFileSystem.writeFileContents(
                memberRoot.appending("Package.swift"),
                string: """
                // swift-tools-version: 999.0
                import PackageDescription

                let package = Package(
                    name: "\(name)",
                    targets: [
                        .target(name: "\(name)"),
                    ],
                )
                """,
            )
            let sourceDir = memberRoot.appending(components: "Sources", name)
            try localFileSystem.createDirectory(sourceDir, recursive: true)
            try localFileSystem.writeFileContents(
                sourceDir.appending("\(name).swift"),
                string: "public enum \(name.replacingOccurrences(of: "-", with: "_")) {}",
            )
        }
    }
}

// MARK: - findEnclosingMember (integration)

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct FindEnclosingMemberIntegrationTests {
    /// End-to-end for the focus-computation wiring: load a real
    /// `Workspace.swift` from disk through `PackageWorkspace.loadWorkspaceManifest`,
    /// then feed its `members` array into `findEnclosingMember` for
    /// a variety of CWDs. Complements the pure-function unit tests in
    /// `WorkspaceManifestTests` by proving the two APIs compose
    /// correctly against a filesystem-loaded manifest.
    @Test(
        .tags(
            Tag.TestSize.medium,
        ),
    )
    func loadedWorkspace_findEnclosingMember_returnsExpectedFocusForCwd() async throws {
        try await withTemporaryDirectory { tempDir in
            let workspaceRoot = tempDir.appending("workspace")
            try WorkspaceManifestTests.writeMinimalWorkspaceAndMembers(
                at: workspaceRoot,
                memberPaths: [
                    "packages/lib-a",
                    "packages/lib-b",
                ],
            )

            let manifestLoader = ManifestLoader(toolchain: try UserToolchain.default)
            let observability = ObservabilitySystem.makeForTesting()

            let manifest = try await PackageWorkspace.loadWorkspaceManifest(
                at: workspaceRoot,
                manifestLoader: manifestLoader,
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope,
            )

            let libAPath = workspaceRoot.appending(components: "packages", "lib-a")
            let libBPath = workspaceRoot.appending(components: "packages", "lib-b")

            #expect(
                PackageWorkspace.findEnclosingMember(
                    cwd: libAPath,
                    in: manifest.members,
                ) == PackageIdentity.plain("lib-a"),
            )
            #expect(
                PackageWorkspace.findEnclosingMember(
                    cwd: libAPath.appending(components: "Sources", "lib-a"),
                    in: manifest.members,
                ) == PackageIdentity.plain("lib-a"),
            )
            #expect(
                PackageWorkspace.findEnclosingMember(
                    cwd: libBPath,
                    in: manifest.members,
                ) == PackageIdentity.plain("lib-b"),
            )
            #expect(
                PackageWorkspace.findEnclosingMember(
                    cwd: workspaceRoot,
                    in: manifest.members,
                ) == nil,
            )
        }
    }

    // MARK: - Encodable

    /// Wire shape mirror for `WorkspaceManifest` JSON. Kept private
    /// to the test suite — production code encodes the manifest via
    /// its `Encodable` conformance, and tests decode into this local
    /// struct rather than reaching into a `[String: Any]` dictionary.
    private struct WorkspaceManifestJSON: Decodable {
        let path: String
        let toolsVersion: String
        let members: [MemberJSON]
        let dependencies: [DependencyJSON]

        struct MemberJSON: Decodable {
            let identity: String
            let path: String
        }

        // PackageDependency's encoded shape is nested and varies by
        // kind; tests here only need to count entries, so we decode
        // to an opaque object.
        struct DependencyJSON: Decodable {}
    }

    /// A workspace manifest with no members and no dependencies
    /// encodes to the expected top-level shape: path, tools version,
    /// and empty arrays for members and dependencies. Locks in that
    /// empty collections still appear (rather than being omitted).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func workspaceManifest_encoding_emptyManifest_emitsExpectedShape() throws {
        let manifest = WorkspaceManifest(
            path: AbsolutePath("/repo/Workspace.swift"),
            toolsVersion: .vNext,
            members: [],
            dependencies: [],
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(WorkspaceManifestJSON.self, from: data)

        #expect(decoded.path == "/repo/Workspace.swift")
        #expect(decoded.toolsVersion == "999.0.0")
        #expect(decoded.members.isEmpty)
        #expect(decoded.dependencies.isEmpty)
    }

    /// Members encode as an array of `{identity, path}` objects — the
    /// two fields a workspace-dump consumer needs to route follow-up
    /// commands (`--package <identity>` selection, member-path
    /// resolution). Internal fields like `ignoredStateDirectories`
    /// are intentionally omitted from the wire shape.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func workspaceManifest_encoding_withMembers_emitsIdentityAndPath() throws {
        let manifest = WorkspaceManifest(
            path: AbsolutePath("/repo/Workspace.swift"),
            toolsVersion: .vNext,
            members: [
                .init(
                    identity: .plain("app"),
                    path: AbsolutePath("/repo/packages/app"),
                ),
                .init(
                    identity: .plain("liba"),
                    path: AbsolutePath("/repo/packages/lib-a"),
                ),
            ],
            dependencies: [],
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(WorkspaceManifestJSON.self, from: data)

        try #require(decoded.members.count == 2)
        #expect(decoded.members[0].identity == "app")
        #expect(decoded.members[0].path == "/repo/packages/app")
        #expect(decoded.members[1].identity == "liba")
        #expect(decoded.members[1].path == "/repo/packages/lib-a")
    }

    /// Dependencies encode via `PackageDependency`'s existing
    /// `Encodable` conformance. This test verifies that a workspace
    /// with a file-system dependency round-trips through JSON and
    /// arrives at the same count on the other side — the exact per-
    /// entry shape is owned by `PackageDependency` and covered by its
    /// own tests.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func workspaceManifest_encoding_withDependencies_preservesCount() throws {
        let manifest = WorkspaceManifest(
            path: AbsolutePath("/repo/Workspace.swift"),
            toolsVersion: .vNext,
            members: [],
            dependencies: [
                .fileSystem(
                    identity: .plain("dep-a"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: AbsolutePath("/repo/vendor/dep-a"),
                    productFilter: .everything,
                    traits: [],
                ),
            ],
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(WorkspaceManifestJSON.self, from: data)

        #expect(decoded.dependencies.count == 1)
    }

    // MARK: - WorkspaceManifestParseError descriptions (Phase 15a)

    /// The `emptyMembers` error prints a user-actionable message
    /// naming `Workspace.swift`. Prior to Phase 15a the error
    /// rendered as raw enum reflection.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func emptyMembers_description_isUserActionable() throws {
        let error = WorkspaceManifestParseError.emptyMembers
        let description = String(describing: error)
        #expect(description.contains("Workspace.swift"))
        #expect(description.contains("no members") || description.contains("empty"))
        // Regression guard: never surface the raw enum name.
        #expect(description.contains("emptyMembers") == false)
    }

    /// The `memberAbsolutePathError` description names the offending
    /// path AND spells out the constraint (paths must be relative
    /// to `Workspace.swift`).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func memberAbsolutePathError_description_namesPathAndConstraint() throws {
        let error = WorkspaceManifestParseError.memberAbsolutePathError(
            memberName: "lib-a",
            path: "/absolute/lib-a",
        )
        let description = String(describing: error)
        #expect(description.contains("/absolute/lib-a"))
        #expect(description.contains("relative"))
        #expect(description.contains("memberAbsolutePathError") == false)
    }

    /// The `duplicateMembernames` description names the colliding
    /// identity so the user knows which entry to rename.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func duplicateMembernames_description_namesTheDuplicate() throws {
        let error = WorkspaceManifestParseError.duplicateMembernames(name: "lib-a")
        let description = String(describing: error)
        #expect(description.contains("'lib-a'"))
        #expect(description.contains("duplicate") || description.contains("collide"))
        #expect(description.contains("duplicateMembernames") == false)
    }

    /// The `memberPathNotFound` description names the missing path
    /// AND the member identity so the user can trace it back to the
    /// declaration in `Workspace.swift`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func memberPathNotFound_description_namesIdentityAndPath() throws {
        let error = WorkspaceManifestParseError.memberPathNotFound(
            memberName: "lib-a",
            path: "/repo/packages/lib-a",
        )
        let description = String(describing: error)
        #expect(description.contains("'lib-a'"))
        #expect(description.contains("/repo/packages/lib-a"))
        #expect(description.contains("memberPathNotFound") == false)
    }

    /// The `memberMissingPackageManifest` description names the
    /// identity, the path, AND the missing `Package.swift` so the
    /// fix is obvious.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func memberMissingPackageManifest_description_namesIdentityPathAndManifest() throws {
        let error = WorkspaceManifestParseError.memberMissingPackageManifest(
            memberName: "lib-a",
            path: "/repo/packages/lib-a",
        )
        let description = String(describing: error)
        #expect(description.contains("'lib-a'"))
        #expect(description.contains("/repo/packages/lib-a"))
        #expect(description.contains("Package.swift"))
        #expect(description.contains("memberMissingPackageManifest") == false)
    }

    // MARK: - Out-of-tree member warning (Phase 15a, item 3)

    /// A member whose path lies OUTSIDE the workspace's directory
    /// tree is legal (SwiftPM supports it) but reduces portability —
    /// checkouts made elsewhere may not find the member. Emit the
    /// concrete `.memberOutsideWorkspaceTree` diagnostic factory so
    /// downstream tools can pattern-match on it, and reconstruct
    /// that factory in the test to check message + severity rather
    /// than pinning to a string literal.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkOutOfTreeMembers_withOutOfTreeMember_emitsWarning() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let workspaceRoot = AbsolutePath("/repo")
        let strayPath = AbsolutePath("/elsewhere/stray")
        let members = [
            WorkspaceManifest.Member(
                identity: .plain("lib-a"),
                path: workspaceRoot.appending(components: "packages", "lib-a"),
            ),
            WorkspaceManifest.Member(
                identity: .plain("stray"),
                path: strayPath,
            ),
        ]

        PackageWorkspace.checkOutOfTreeMembers(
            members,
            workspaceRoot: workspaceRoot,
            observabilityScope: observability.topScope,
        )

        try #require(observability.diagnostics.count == 1)
        let actual = try #require(observability.diagnostics.first)
        let expected = Basics.Diagnostic.memberOutsideWorkspaceTree(
            memberIdentity: .plain("stray"),
            memberPath: strayPath,
            workspaceRoot: workspaceRoot,
        )
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// When every member lives inside the workspace tree, no
    /// warning fires. Regression guard for the check's early exit.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkOutOfTreeMembers_withAllInTree_emitsNothing() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let workspaceRoot = AbsolutePath("/repo")
        let members = [
            WorkspaceManifest.Member(
                identity: .plain("lib-a"),
                path: workspaceRoot.appending(components: "packages", "lib-a"),
            ),
            WorkspaceManifest.Member(
                identity: .plain("lib-b"),
                path: workspaceRoot.appending(components: "packages", "lib-b"),
            ),
        ]

        PackageWorkspace.checkOutOfTreeMembers(
            members,
            workspaceRoot: workspaceRoot,
            observabilityScope: observability.topScope,
        )

        #expect(observability.diagnostics.isEmpty)
    }

    /// A member whose path equals the workspace root itself is
    /// technically in-tree (root is ancestor-or-equal). Doesn't
    /// warn. Locks in the boundary condition.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkOutOfTreeMembers_withMemberAtWorkspaceRoot_emitsNothing() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let workspaceRoot = AbsolutePath("/repo")
        let members = [
            WorkspaceManifest.Member(
                identity: .plain("root-member"),
                path: workspaceRoot,
            ),
        ]

        PackageWorkspace.checkOutOfTreeMembers(
            members,
            workspaceRoot: workspaceRoot,
            observabilityScope: observability.topScope,
        )

        #expect(observability.diagnostics.isEmpty)
    }

    // MARK: - Nested workspace detection (Phase 15b)

    /// Item 7: If a `Workspace.swift` sits in an ancestor of the
    /// discovered workspace root, we've got a nested workspace.
    /// SwiftPM doesn't support that shape — the semantics of "which
    /// workspace's `.build/` is the shared one" are undefined. Hard
    /// error at load time listing BOTH paths so the author can see
    /// the collision and remove one.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkNestedWorkspaceInAncestors_withAncestorWorkspace_throws() throws {
        let fileSystem = InMemoryFileSystem()
        let outerRoot = AbsolutePath("/outer")
        let innerRoot = outerRoot.appending(components: "inner")
        try fileSystem.createDirectory(innerRoot, recursive: true)
        try fileSystem.writeFileContents(
            outerRoot.appending(WorkspaceManifest.filename),
            string: "",
        )

        #expect(
            throws: WorkspaceManifestParseError.nestedWorkspaceInAncestor(
                inner: innerRoot,
                outer: outerRoot,
            ),
        ) {
            try PackageWorkspace.checkNestedWorkspaceInAncestors(
                workspaceRoot: innerRoot,
                fileSystem: fileSystem,
            )
        }
    }

    /// The passthrough case: no ancestor holds a `Workspace.swift`.
    /// Regression guard for the walk's terminating condition.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkNestedWorkspaceInAncestors_withNoAncestorWorkspace_doesNotThrow() throws {
        let fileSystem = InMemoryFileSystem()
        let workspaceRoot = AbsolutePath("/repo")
        try fileSystem.createDirectory(workspaceRoot, recursive: true)

        try PackageWorkspace.checkNestedWorkspaceInAncestors(
            workspaceRoot: workspaceRoot,
            fileSystem: fileSystem,
        )
    }

    /// The `nestedWorkspaceInAncestor` error's description names
    /// BOTH paths so the author can locate each `Workspace.swift`
    /// without hunting the tree.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func nestedWorkspaceInAncestor_description_namesBothPaths() throws {
        let error = WorkspaceManifestParseError.nestedWorkspaceInAncestor(
            inner: AbsolutePath("/outer/inner"),
            outer: AbsolutePath("/outer"),
        )
        let description = String(describing: error)
        #expect(description.contains("/outer/inner"))
        #expect(description.contains("/outer"))
        #expect(description.contains("nested"))
        #expect(description.contains("nestedWorkspaceInAncestor") == false)
    }

    /// Item 6: A workspace member's directory contains its OWN
    /// `Workspace.swift`. Same shared-state ambiguity as item 7 but
    /// discovered downward from the load site rather than upward.
    /// Throws with the offending member's identity + path so the
    /// author knows which member to inspect.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkNestedWorkspaceInMembers_withMemberContainingWorkspaceSwift_throws() throws {
        let fileSystem = InMemoryFileSystem()
        let workspaceRoot = AbsolutePath("/repo")
        let libAPath = workspaceRoot.appending(components: "packages", "lib-a")
        let strayWorkspace = libAPath.appending(WorkspaceManifest.filename)
        try fileSystem.createDirectory(libAPath, recursive: true)
        try fileSystem.writeFileContents(strayWorkspace, string: "")

        let members = [
            WorkspaceManifest.Member(
                identity: .plain("lib-a"),
                path: libAPath,
            ),
        ]

        #expect(
            throws: WorkspaceManifestParseError.nestedWorkspaceInMember(
                memberName: "lib-a",
                nestedWorkspacePath: strayWorkspace,
            ),
        ) {
            try PackageWorkspace.checkNestedWorkspaceInMembers(
                members,
                fileSystem: fileSystem,
            )
        }
    }

    /// Members with no nested `Workspace.swift` pass through. The
    /// check is silent for well-formed layouts.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func checkNestedWorkspaceInMembers_withCleanMembers_doesNotThrow() throws {
        let fileSystem = InMemoryFileSystem()
        let workspaceRoot = AbsolutePath("/repo")
        let libAPath = workspaceRoot.appending(components: "packages", "lib-a")
        try fileSystem.createDirectory(libAPath, recursive: true)

        let members = [
            WorkspaceManifest.Member(
                identity: .plain("lib-a"),
                path: libAPath,
            ),
        ]

        try PackageWorkspace.checkNestedWorkspaceInMembers(
            members,
            fileSystem: fileSystem,
        )
    }

    /// The `nestedWorkspaceInMember` description names both the
    /// offending member and the path of the stray `Workspace.swift`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func nestedWorkspaceInMember_description_namesMemberAndPath() throws {
        let error = WorkspaceManifestParseError.nestedWorkspaceInMember(
            memberName: "lib-a",
            nestedWorkspacePath: AbsolutePath("/repo/packages/lib-a/Workspace.swift"),
        )
        let description = String(describing: error)
        #expect(description.contains("'lib-a'"))
        #expect(description.contains("/repo/packages/lib-a/Workspace.swift"))
        #expect(description.contains("nested"))
        #expect(description.contains("nestedWorkspaceInMember") == false)
    }
}
