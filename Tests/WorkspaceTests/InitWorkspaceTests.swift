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
import PackageModel
import Testing
import _InternalTestSupport
@testable import Workspace

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct InitWorkspaceTests {
    /// Bare `init workspace` (no `--members`) creates a
    /// `Workspace.swift` file with an empty `members: []` list.
    /// Users then edit the file to add members by hand.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func write_withNoMembers_createsWorkspaceManifestWithEmptyMembers() throws {
        let root = AbsolutePath("/repo")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(root, recursive: true)

        try InitWorkspace(
            fileSystem: fileSystem,
            destinationPath: root,
            options: .init(members: []),
        ).write()

        let manifestPath = root.appending("Workspace.swift")
        try #require(fileSystem.exists(manifestPath))
        let content: String = try fileSystem.readFileContents(manifestPath)
        #expect(content.contains("import PackageDescription"))
        #expect(content.contains("let workspace = Workspace("))
        #expect(content.contains("members: []"))
    }

    /// `--members packages/lib-a` scaffolds `packages/lib-a/Package.swift`
    /// and lists it in `Workspace.swift`. Uses `.empty` because
    /// `InitPackage.writeSources()` for library/executable reads bundle
    /// resource templates that don't exist on `InMemoryFileSystem`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func write_withOneMember_scaffoldsMemberAndListsIt() throws {
        let root = AbsolutePath("/repo")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(root, recursive: true)

        try InitWorkspace(
            fileSystem: fileSystem,
            destinationPath: root,
            options: .init(members: [
                .init(path: "packages/lib-a", packageType: .empty),
            ]),
        ).write()

        let manifestPath = root.appending("Workspace.swift")
        let manifestContent: String = try fileSystem.readFileContents(manifestPath)
        #expect(manifestContent.contains("\"packages/lib-a\""))

        let memberManifest = root.appending(
            try RelativePath(validating: "packages/lib-a/Package.swift"),
        )
        #expect(fileSystem.exists(memberManifest))
    }

    /// Two members both get scaffolded and both appear in the manifest
    /// in declared order. Uses `.empty` for both because
    /// `InitPackage.writeSources()` for other types reads bundle resource
    /// templates that don't exist on `InMemoryFileSystem`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func write_withMultipleMembers_scaffoldsAllInOrder() throws {
        let root = AbsolutePath("/repo")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(root, recursive: true)

        try InitWorkspace(
            fileSystem: fileSystem,
            destinationPath: root,
            options: .init(members: [
                .init(path: "packages/lib-a", packageType: .empty),
                .init(path: "packages/app", packageType: .empty),
            ],
        ),
        ).write()

        let manifestContent: String = try fileSystem.readFileContents(root.appending("Workspace.swift"))
        let libAIndex = try #require(manifestContent.range(of: "\"packages/lib-a\""))
        let appIndex = try #require(manifestContent.range(of: "\"packages/app\""))
        #expect(libAIndex.lowerBound < appIndex.lowerBound, "members should appear in declared order")

        #expect(fileSystem.exists(root.appending(try RelativePath(validating: "packages/lib-a/Package.swift"))))
        #expect(fileSystem.exists(root.appending(try RelativePath(validating: "packages/app/Package.swift"))))
    }

    /// A pre-existing `Workspace.swift` at the destination is a hard
    /// error — `init workspace` never overwrites. Users must remove
    /// the existing file themselves if they want to regenerate.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func write_whenWorkspaceManifestAlreadyExists_throws() throws {
        let root = AbsolutePath("/repo")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(root, recursive: true)
        try fileSystem.writeFileContents(root.appending("Workspace.swift"), string: "// pre-existing\n")

        #expect(throws: InitWorkspaceError.workspaceManifestAlreadyExists(root.appending("Workspace.swift"))) {
            try InitWorkspace(
                fileSystem: fileSystem,
                destinationPath: root,
                options: .init(members: []),
            ).write()
        }
    }

    /// A member path that already has its own `Package.swift` is
    /// listed in the new `Workspace.swift` but its existing manifest
    /// is left byte-identical — `init workspace` is safe to run in a
    /// directory that already contains packages.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func write_whenMemberHasExistingPackageManifest_preservesIt() throws {
        let root = AbsolutePath("/repo")
        let fileSystem = InMemoryFileSystem()
        let memberDir = root.appending(try RelativePath(validating: "packages/lib-a"))
        try fileSystem.createDirectory(memberDir, recursive: true)
        let originalContent = "// pre-existing member manifest\n"
        try fileSystem.writeFileContents(
            memberDir.appending("Package.swift"),
            string: originalContent,
        )

        try InitWorkspace(
            fileSystem: fileSystem,
            destinationPath: root,
            options: .init(members: [
                .init(path: "packages/lib-a", packageType: .library),
            ]),
        ).write()

        let afterContent: String = try fileSystem.readFileContents(memberDir.appending("Package.swift"))
        #expect(afterContent == originalContent)

        let manifestContent: String = try fileSystem.readFileContents(root.appending("Workspace.swift"))
        #expect(manifestContent.contains("\"packages/lib-a\""))
    }

    /// An absolute path in `--members` is rejected — member paths
    /// must be relative to the workspace root. The parse-time error
    /// catches this before any files are touched.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func write_withAbsoluteMemberPath_throws() throws {
        let root = AbsolutePath("/repo")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(root, recursive: true)

        #expect(throws: InitWorkspaceError.absoluteMemberPath("/absolute/lib-a")) {
            try InitWorkspace(
                fileSystem: fileSystem,
                destinationPath: root,
                options: .init(members: [
                    .init(path: "/absolute/lib-a", packageType: .library),
                ]),
            ).write()
        }
    }
}
