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
@_spi(SwiftPMInternal) @testable import CoreCommands
import PackageModel
import Testing
import _InternalTestSupport

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct MemberStateFindingsTests {
    // MARK: - formatWarning

    /// No findings → no diagnostics. Callers pipe the returned array
    /// straight through the observability sink; an empty array is a
    /// no-op.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func formatWarning_withNoFindings_returnsEmpty() throws {
        let actual = MemberStateFindings.formatWarning(findings: [])
        #expect(actual == nil)
    }

    /// Single member with a single detected state file: one
    /// aggregated warning diagnostic — assembled by the
    /// `workspaceMembersHaveIgnoredState` factory from that finding.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func formatWarning_withOneMemberAndOneKind_producesSingleWarning() throws {
        let findings = [
            MemberStateFindings(
                memberIdentity: .plain("lib-a"),
                detectedStateFiles: [.build],
            ),
        ]
        let expected = Basics.Diagnostic.workspaceMembersHaveIgnoredState(findings: findings)
        let actual = try #require(
            MemberStateFindings.formatWarning(findings: findings),
            "expected a diagnostic",
        )
        #expect(actual == expected)
    }

    /// Multiple members and multiple kinds fold into a single
    /// aggregated warning. `formatWarning` delegates to
    /// `workspaceMembersHaveIgnoredState`, which owns the sort and
    /// formatting rules so downstream stderr order is deterministic.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func formatWarning_withMultipleMembersAndKinds_isDeterministicallyOrdered() throws {
        let findings = [
            MemberStateFindings(
                memberIdentity: .plain("lib-b"),
                detectedStateFiles: [.swiftpmConfig],
            ),
            MemberStateFindings(
                memberIdentity: .plain("lib-a"),
                detectedStateFiles: [.build, .packageResolved],
            ),
        ]
        let expected = Basics.Diagnostic.workspaceMembersHaveIgnoredState(findings: findings)
        let actual = try #require(
            MemberStateFindings.formatWarning(findings: findings),
            "expected a diagnostic to be emitted",
        )
        #expect(actual == expected)
    }

    /// Locks down the exact warning message shape emitted by
    /// `workspaceMembersHaveIgnoredState` for a representative
    /// two-member / mixed-kind input. If the message text needs to
    /// change (e.g. for localization or wording tweaks), this test is
    /// the single place to update — every other test asserts against
    /// the factory itself.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func workspaceMembersHaveIgnoredState_producesExpectedMessage() throws {
        let findings = [
            MemberStateFindings(
                memberIdentity: .plain("lib-b"),
                detectedStateFiles: [.swiftpmConfig],
            ),
            MemberStateFindings(
                memberIdentity: .plain("lib-a"),
                detectedStateFiles: [.build, .packageResolved],
            ),
        ]
        let actual: Basics.Diagnostic = .workspaceMembersHaveIgnoredState(findings: findings)
        let expected: Basics.Diagnostic = .warning("""
            workspace members have ignored state:
              lib-a: .build/, Package.resolved
              lib-b: .swiftpm/configuration/
            Only workspace-root state is used.
            """)
        #expect(actual == expected)
    }

    // MARK: - scanMemberStateFiles

    /// A member with none of the state directories/files on disk
    /// produces no finding — the scanner returns nil so the caller
    /// doesn't add an empty entry to the aggregator.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func scanMemberStateFiles_withCleanMember_returnsNil() throws {
        let memberPath = AbsolutePath("/Workspace/packages/lib-a")
        let fs = InMemoryFileSystem()
        try fs.createDirectory(memberPath, recursive: true)

        let member = WorkspaceManifest.Member(
            identity: .plain("lib-a"),
            path: memberPath,
            ignoredStateDirectories: [],
        )
        let actual = MemberStateFindings.scanMemberStateFiles(
            member: member,
            fileSystem: fs,
        )
        #expect(actual == nil)
    }

    /// A member with `.build/`, `Package.resolved`, `Packages/`, and
    /// `.swiftpm/configuration/` on disk produces a finding that lists
    /// all four kinds. Covers the full detection surface.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func scanMemberStateFiles_withAllStateKindsPresent_reportsAll() throws {
        let memberPath = AbsolutePath("/Workspace/packages/lib-a")
        let fs = InMemoryFileSystem()
        try fs.createDirectory(memberPath.appending(".build"), recursive: true)
        try fs.writeFileContents(memberPath.appending("Package.resolved"), string: "{}")
        try fs.createDirectory(memberPath.appending("Packages"), recursive: true)
        try fs.createDirectory(
            memberPath.appending(components: ".swiftpm", "configuration"),
            recursive: true,
        )

        let member = WorkspaceManifest.Member(
            identity: .plain("lib-a"),
            path: memberPath,
            ignoredStateDirectories: [],
        )
        let actual = try #require(
            MemberStateFindings.scanMemberStateFiles(
                member: member,
                fileSystem: fs,
            ),
        )
        #expect(actual.memberIdentity == .plain("lib-a"))
        #expect(actual.detectedStateFiles == [.build, .packageResolved, .packages, .swiftpmConfig])
    }

    // MARK: - ignoredStateDirectories filtering (Slice 8d)

    /// A kind that appears in both `detected` and
    /// `ignoredStateDirectories` is subtracted from the reported set.
    /// The remaining kinds still trigger a finding.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func scanMemberStateFiles_withIgnoredKind_subtractsFromReported() throws {
        let memberPath = AbsolutePath("/Workspace/packages/lib-b")
        let fs = InMemoryFileSystem()
        try fs.createDirectory(memberPath.appending(".build"), recursive: true)
        try fs.writeFileContents(memberPath.appending("Package.resolved"), string: "{}")

        let member = WorkspaceManifest.Member(
            identity: .plain("lib-b"),
            path: memberPath,
            ignoredStateDirectories: [.build],
        )
        let actual = try #require(
            MemberStateFindings.scanMemberStateFiles(
                member: member,
                fileSystem: fs,
            ),
        )
        #expect(actual.detectedStateFiles == [.packageResolved])
    }

    /// When every detected kind is in the member's
    /// `ignoredStateDirectories`, the scanner returns nil so the
    /// member is completely omitted from the trailing warning.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func scanMemberStateFiles_withAllDetectedKindsIgnored_returnsNil() throws {
        let memberPath = AbsolutePath("/Workspace/packages/lib-b")
        let fs = InMemoryFileSystem()
        try fs.createDirectory(memberPath.appending(".build"), recursive: true)

        let member = WorkspaceManifest.Member(
            identity: .plain("lib-b"),
            path: memberPath,
            ignoredStateDirectories: [.build],
        )
        let actual = MemberStateFindings.scanMemberStateFiles(
            member: member,
            fileSystem: fs,
        )
        #expect(actual == nil)
    }
}
