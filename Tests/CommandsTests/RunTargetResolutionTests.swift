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
@_spi(SwiftPMInternal) @testable import Commands
@_spi(SwiftPMInternal) import CoreCommands
import PackageModel
@_spi(SwiftPMInternal) import SPMBuildCore
import Testing

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct RunTargetResolutionTests {
    // MARK: - Explicit executable across the workspace

    /// Explicit `swift run hello` at workspace root, only one member
    /// declares `hello`: resolves to that member's product, with no
    /// package focus (since disambiguation isn't required).
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_uniqueAcrossMembers_returnsProduct() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["other"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// Explicit `swift run hello` at workspace root, two members
    /// declare `hello`: emit `ambiguousExecutable` listing both
    /// candidates and return nil.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_ambiguousAcrossMembers_returnsNilAndEmitsDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.ambiguousExecutable(
            requested: "hello",
            candidates: [
                (member: .plain("member-a"), product: "hello"),
                (member: .plain("member-b"), product: "hello"),
            ],
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// Explicit `swift run doesnotexist` at workspace root, no member
    /// declares it: emit a `executableNotFoundInWorkspace` diagnostic
    /// and return nil.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_notFoundAcrossMembers_returnsNilAndEmitsDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "does-not-exist",
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["other"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.executableNotFoundInWorkspace(
            requested: "does-not-exist",
            known: [
                .plain("member-a"): [.plain("hello")],
                .plain("member-b"): [.plain("other")],
            ],
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    // MARK: - --package selector

    /// Explicit `swift run --package member-a hello` disambiguates
    /// across ambiguous members: resolves to member-a's `hello`, with
    /// packageFocus = member-a.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_withSelectedPackage_resolvesInMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: .plain("member-a"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package X exec` where `exec` is not declared in `X`: emit
    /// `executableNotFoundInMember` and return nil.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_withSelectedPackage_notInMember_returnsNilAndEmitsDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: .plain("member-b"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["other"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.executableNotFoundInMember(
            requested: "hello",
            package: .plain("member-b"),
            known: [.plain("other")],
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `--package UNKNOWN exec` errors on the `--package` validation
    /// before touching executable resolution.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_withUnknownSelectedPackage_returnsNilAndEmitsError() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [
            .plain("member-a"),
            .plain("member-b"),
        ]

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: .plain("no-such"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: known,
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.unknownWorkspaceMember(
            requested: .plain("no-such"),
            known: known,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `--package X` outside a workspace: emit
    /// `packageSelectorRequiresWorkspace` and return nil.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_withSelectedPackageOutsideWorkspace_returnsNilAndEmitsError() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: .plain("member-a"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: nil,
            executablesByMember: [
                .plain("standalone"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.packageSelectorRequiresWorkspace(
            requested: .plain("member-a"),
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    // MARK: - CWD-inside-member (workspaceMemberFocus)

    /// From inside member-a (Case A): `swift run hello` resolves to
    /// member-a's `hello`, even though member-b also declares `hello`.
    /// No ambiguity — focus scopes the lookup.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_withWorkspaceMemberFocus_resolvesInFocusedMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: nil,
            workspaceMemberFocus: .plain("member-a"),
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// From inside member-a: `swift run <other-member-exec>` MUST NOT
    /// be silently found via cross-member search. Emit
    /// `executableNotFoundInMember` for member-a listing its known
    /// executables.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_explicit_withWorkspaceMemberFocus_notInMember_returnsNilAndEmitsDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "unique",
            selectedPackage: nil,
            workspaceMemberFocus: .plain("member-a"),
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-c"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-c"): ["unique"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.executableNotFoundInMember(
            requested: "unique",
            package: .plain("member-a"),
            known: [.plain("hello")],
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `--package X` supplied from inside a DIFFERENT member `Y`:
    /// `--package` wins over CWD focus — the resolution is done in X.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_selectedPackageOverridesFocus_resolvesInSelectedPackage() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: .plain("member-b"),
            workspaceMemberFocus: .plain("member-a"),
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-b"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    // MARK: - Implicit executable (no name given)

    /// Implicit `swift run` at workspace root, exactly one executable
    /// across all members: resolves to that one product.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_singleExecutableAcrossMembers_resolves() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): [],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// Implicit `swift run` at workspace root, multiple executables:
    /// emit multipleExecutables diagnostic listing them.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_multipleExecutables_returnsNilAndEmitsDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["other"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.multipleExecutablesInWorkspace(
            candidates: [
                (member: .plain("member-a"), product: "hello"),
                (member: .plain("member-b"), product: "other"),
            ],
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// Implicit `swift run` when no executable is declared in any
    /// member: emit noExecutableFound.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_noExecutables_returnsNilAndEmitsDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: [.plain("member-a")],
            executablesByMember: [.plain("member-a"): []],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.noExecutableFoundInWorkspace()
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// Implicit `swift run --package X` with a single exec in X: resolve.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_withSelectedPackage_resolvesInMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: .plain("member-a"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// Implicit `swift run` from inside member-a: only member-a's
    /// executables count.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_withWorkspaceMemberFocus_resolvesInMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: nil,
            workspaceMemberFocus: .plain("member-a"),
            availableMemberIdentities: [
                .plain("member-a"),
                .plain("member-b"),
            ],
            executablesByMember: [
                .plain("member-a"): ["hello"],
                .plain("member-b"): ["also"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    // MARK: - Scoped-to-member with no executables

    /// Implicit `swift run --package X` where X declares no
    /// executables: emit `noExecutableFoundInMember(X)` — the scoped
    /// variant of `noExecutableFoundInWorkspace`.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_withSelectedPackageAndNoExecutables_emitsScopedDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: .plain("lib-a"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                .plain("lib-a"),
                .plain("member-a"),
            ],
            executablesByMember: [
                .plain("lib-a"): [],
                .plain("member-a"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.noExecutableFoundInMember(package: .plain("lib-a"))
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// Implicit `swift run` from inside a library-only member (Case A
    /// focus, no `--package`): emit `noExecutableFoundInMember(A)` —
    /// the scoped variant, because the resolver never falls back to
    /// searching other members when a focus is set.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_implicit_withWorkspaceMemberFocusAndNoExecutables_emitsScopedDiagnostic() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: nil,
            selectedPackage: nil,
            workspaceMemberFocus: .plain("lib-a"),
            availableMemberIdentities: [
                .plain("lib-a"),
                .plain("member-a"),
            ],
            executablesByMember: [
                .plain("lib-a"): [],
                .plain("member-a"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(target == nil)
        let expected = Diagnostic.noExecutableFoundInMember(package: .plain("lib-a"))
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `swift run --package member-a hello` from inside library-only
    /// member `lib-a`: `--package` overrides the CWD focus, and the
    /// executable is resolved in the selected member. Confirms
    /// `--package` provides an escape hatch from a member that has
    /// nothing to run.
    @Test(
        .tags(Tag.TestSize.small),
    )
    func resolveRunTarget_selectedPackageOverridesLibOnlyFocus_resolvesInSelectedPackage() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let target = RunCommandOptions.resolveRunTarget(
            requestedExecutable: "hello",
            selectedPackage: .plain("member-a"),
            workspaceMemberFocus: .plain("lib-a"),
            availableMemberIdentities: [
                .plain("lib-a"),
                .plain("member-a"),
            ],
            executablesByMember: [
                .plain("lib-a"): [],
                .plain("member-a"): ["hello"],
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            target == ResolvedRunTarget(
                productName: "hello",
                packageFocus: .plain("member-a"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }
}
