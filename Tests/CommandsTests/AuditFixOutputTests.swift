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
import PackageAudit
import PackageGraph
import PackageModel
import Testing
import Workspace

@testable
import Commands

import struct TSCUtility.Version

struct AuditFixOutputTests {
    private static func reference(_ name: String) -> PackageReference {
        .remoteSourceControl(identity: .plain(name), url: SourceControlURL("https://example.com/\(name)"))
    }

    private static func versionState(_ version: String) -> Workspace.PackageStateChange.State {
        .init(requirement: .version(Version(stringLiteral: version)), products: .everything)
    }

    /// An update within the declared requirements can add or drop transitive dependencies,
    /// which are listed along with the updated packages.
    private static let changes: [(PackageReference, Workspace.PackageStateChange)] = [
        (reference("foo"), .updated(versionState("1.1.0"))),
        (reference("bar"), .added(versionState("2.0.0"))),
        (reference("baz"), .removed),
        (reference("qux"), .unchanged),
    ]

    private static let oldPins: ResolvedPackagesStore.ResolvedPackages = [
        .plain("foo"): .init(packageRef: reference("foo"), state: .version("1.0.0", revision: nil), originalScmUrl: nil),
        .plain("baz"): .init(packageRef: reference("baz"), state: .version("0.9.0", revision: nil), originalScmUrl: nil),
        .plain("qux"): .init(packageRef: reference("qux"), state: .version("3.0.0", revision: nil), originalScmUrl: nil),
    ]

    private static let emptyReport = AuditReport(scannedPackages: 0, findings: [], unchecked: [])

    @Test
    func dryRunListsAddedAndRemovedDependencies() {
        let lines = SwiftPackageCommand.Audit.Fix.updateLines(
            Self.changes, oldPins: Self.oldPins, report: Self.emptyReport, dryRun: true
        )
        #expect(lines == [
            "Would update https://example.com/foo 1.0.0 -> 1.1.0 (Package.resolved)",
            "Would add https://example.com/bar 2.0.0 (Package.resolved)",
            "Would remove https://example.com/baz 0.9.0 (Package.resolved)",
        ])
    }

    @Test
    func appliedChangesUsePastTense() {
        let lines = SwiftPackageCommand.Audit.Fix.updateLines(
            Self.changes, oldPins: Self.oldPins, report: Self.emptyReport, dryRun: false
        )
        #expect(lines == [
            "Updated https://example.com/foo 1.0.0 -> 1.1.0 (Package.resolved)",
            "Added https://example.com/bar 2.0.0 (Package.resolved)",
            "Removed https://example.com/baz 0.9.0 (Package.resolved)",
        ])
    }
}
