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

@testable import Commands
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
    /// shape emitted by `swift package workspace init` when no
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
    /// `swift package workspace override list`, keeping list output
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
}
