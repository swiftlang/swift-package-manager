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

/// A summary of the member-level state files SwiftPM detected under a
/// workspace member but did not use, because workspace-scoped state
/// takes precedence.
///
/// A finding is only produced for a member when at least one state
/// kind was detected AND that kind was not listed in the member's
/// `ignoredStateDirectories`. Empty findings never reach the
/// aggregator; the scanner returns `nil` in that case.
public struct MemberStateFindings: Sendable, Equatable {
    /// The identity of the workspace member the state files were
    /// found under.
    public let memberIdentity: PackageIdentity

    /// The state-file kinds that were detected AND not ignored — the
    /// set the trailing warning should report for this member.
    public let detectedStateFiles: Set<WorkspaceManifest.StateDirectoryKind>

    public init(
        memberIdentity: PackageIdentity,
        detectedStateFiles: Set<WorkspaceManifest.StateDirectoryKind>,
    ) {
        self.memberIdentity = memberIdentity
        self.detectedStateFiles = detectedStateFiles
    }
}

extension MemberStateFindings {
    /// Detect member-level state files on disk and produce a
    /// `MemberStateFindings` for the member — or `nil` when the member
    /// has nothing worth reporting (either no detected state, or every
    /// detected kind is in the member's `ignoredStateDirectories`).
    ///
    /// Pure over the injected `FileSystem`: swap in `InMemoryFileSystem`
    /// for unit tests.
    static func scanMemberStateFiles(
        member: WorkspaceManifest.Member,
        fileSystem: FileSystem,
    ) -> MemberStateFindings? {
        var detected: Set<WorkspaceManifest.StateDirectoryKind> = []
        for kind in WorkspaceManifest.StateDirectoryKind.allCases {
            if kind.exists(under: member.path, fileSystem: fileSystem) {
                detected.insert(kind)
            }
        }
        let reported = detected.subtracting(member.ignoredStateDirectories)
        guard !reported.isEmpty else { return nil }
        return MemberStateFindings(
            memberIdentity: member.identity,
            detectedStateFiles: reported,
        )
    }

    /// Convert a list of `MemberStateFindings` into the warning
    /// diagnostics to emit at end of command. Currently produces at
    /// most one aggregated warning that lists every member and its
    /// detected state kinds; returns an empty array when there are no
    /// findings so callers can pipe the result straight through the
    /// observability sink without a nil check.
    static func formatWarning(findings: [MemberStateFindings]) -> Basics.Diagnostic? {
        guard !findings.isEmpty else { return nil }
        return .workspaceMembersHaveIgnoredState(findings: findings)
    }
}

extension WorkspaceManifest.StateDirectoryKind: CaseIterable {
    public static let allCases: [WorkspaceManifest.StateDirectoryKind] = [
        .build,
        .packageResolved,
        .packages,
        .swiftpmConfig,
    ]

    /// The relative path (as displayed in the trailing warning) for
    /// this state-directory kind. Directory kinds include a trailing
    /// `/` so users can distinguish a directory from a plain file at
    /// a glance.
    var pathComponent: String {
        switch self {
        case .build: ".build/"
        case .packageResolved: "Package.resolved"
        case .packages: "Packages/"
        case .swiftpmConfig: ".swiftpm/configuration/"
        }
    }

    /// Whether this state kind exists under `memberPath` on the given
    /// filesystem. Directory kinds check for a directory; the
    /// file-shaped kind checks for a regular file.
    func exists(under memberPath: AbsolutePath, fileSystem: FileSystem) -> Bool {
        switch self {
        case .build:
            fileSystem.isDirectory(memberPath.appending(".build"))
        case .packageResolved:
            fileSystem.exists(memberPath.appending("Package.resolved"))
        case .packages:
            fileSystem.isDirectory(memberPath.appending("Packages"))
        case .swiftpmConfig:
            fileSystem.isDirectory(memberPath.appending(components: ".swiftpm", "configuration"))
        }
    }
}

extension Basics.Diagnostic {
    /// Aggregated warning emitted at end-of-command when one or more
    /// workspace members have their own local state files
    /// (`.build/`, `Package.resolved`, etc.) that SwiftPM detected
    /// but did not use. The workspace root owns the authoritative
    /// state; per-member state is ignored. This warning tells the
    /// user which members have stale local state that could be
    /// deleted or moved to the workspace root.
    ///
    /// Members are alphabetized by identity; kinds within a member's
    /// line are alphabetized by their filesystem path component. The
    /// ordering is fixed here so downstream stderr output is
    /// deterministic across runs.
    @_spi(SwiftPMInternal)
    public static func workspaceMembersHaveIgnoredState(
        findings: [MemberStateFindings],
    ) -> Self {
        let lines = findings
            .sorted { $0.memberIdentity.description < $1.memberIdentity.description }
            .map { finding in
                let kinds = finding.detectedStateFiles
                    .sorted { $0.pathComponent < $1.pathComponent }
                    .map(\.pathComponent)
                    .joined(separator: ", ")
                return "      - \(finding.memberIdentity): \(kinds)"
            }
            .joined(separator: "\n")
        return .warning("""
            workspace members have ignored state:
            \(lines)
                Only workspace-root state is used.
            """)
    }
}
