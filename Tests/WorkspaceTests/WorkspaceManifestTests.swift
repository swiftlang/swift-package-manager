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
import Workspace

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

        let result = try WorkspaceManifestJSONParser.parse(
            v2: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(result.members.count == 1)
        let member = result.members[0]
        #expect(member.path == workspaceRoot.appending(components: "packages", "lib-a"))
        #expect(member.identity == PackageIdentity(path: member.path))
        #expect(member.ignoredStateDirectories.isEmpty)
        #expect(result.dependencies.isEmpty)
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
    private static func writeMinimalWorkspaceAndMembers(
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
