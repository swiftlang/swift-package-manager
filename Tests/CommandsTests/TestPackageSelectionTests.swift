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
@testable import Commands
@_spi(SwiftPMInternal) import CoreCommands
import PackageModel
import Testing

import func _InternalTestSupport.expectNoDiagnostics


@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct TestPackageSelectionTests {
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveSelectedPackage_withNilSelected_returnsNilNoError() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let resolved = TestCommandOptions.resolveSelectedPackage(
            selected: nil,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(resolved == nil)
        expectNoDiagnostics(observability.diagnostics)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveSelectedPackage_withValidSelected_returnsSelected() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let members: Set<PackageIdentity> = [
            PackageIdentity.plain("lib-a"),
            PackageIdentity.plain("lib-b"),
        ]

        let resolved = TestCommandOptions.resolveSelectedPackage(
            selected: PackageIdentity.plain("lib-a"),
            availableMemberIdentities: members,
            observabilityScope: observability.topScope,
        )

        #expect(resolved == PackageIdentity.plain("lib-a"))
        expectNoDiagnostics(observability.diagnostics)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveSelectedPackage_withUnknownSelected_returnsNilAndEmitsUnknownMemberError() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let members: Set<PackageIdentity> = [
            PackageIdentity.plain("lib-a"),
        ]
        let requested = PackageIdentity.plain("does-not-exist")

        let resolved = TestCommandOptions.resolveSelectedPackage(
            selected: requested,
            availableMemberIdentities: members,
            observabilityScope: observability.topScope,
        )

        #expect(resolved == nil)
        let expected = Basics.Diagnostic.unknownWorkspaceMember(
            requested: requested,
            known: members,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveSelectedPackage_withSelectedButNoWorkspace_returnsNilAndEmitsRequiresWorkspaceError() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let requested = PackageIdentity.plain("lib-a")

        let resolved = TestCommandOptions.resolveSelectedPackage(
            selected: requested,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(resolved == nil)
        let expected = Basics.Diagnostic.packageSelectorRequiresWorkspace(requested: requested)
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }
}
