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
import SPMBuildCore
import Testing

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct BuildSubsetSelectionTests {
    /// Explicit `--product` wins over any implicit selection (including
    /// workspace-member focus).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withExplicitProduct_returnsProduct() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: "app",
            target: nil,
            buildTests: false,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == .product("app"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withExplicitProductAndFocus_prefersExplicitProduct() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: "app",
            target: nil,
            buildTests: false,
            workspaceMemberFocus: PackageIdentity.plain("app"),
            observabilityScope: observability.topScope,
        )

        #expect(subset == .product("app"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withExplicitTarget_returnsTarget() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: "AppTarget",
            buildTests: false,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == .target("AppTarget"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withExplicitTargetAndFocus_prefersExplicitTarget() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: "AppTarget",
            buildTests: false,
            workspaceMemberFocus: PackageIdentity.plain("app"),
            observabilityScope: observability.topScope,
        )

        #expect(subset == .target("AppTarget"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withBuildTests_returnsAllIncludingTests() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: true,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == .allIncludingTests())
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withBuildTestsAndFocus_prefersBuildTests() throws {
        // `--build-tests` is a superset request that spans the whole
        // workspace's test targets; the focus should not shrink it.
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: true,
            workspaceMemberFocus: PackageIdentity.plain("app"),
            observabilityScope: observability.topScope,
        )

        #expect(subset == .allIncludingTests())
    }

    /// The core Slice 4 behavior: no explicit override and CWD inside a
    /// workspace member yields `.workspaceMember(id)`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withOnlyFocus_returnsWorkspaceMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            workspaceMemberFocus: PackageIdentity.plain("app"),
            observabilityScope: observability.topScope,
        )

        #expect(subset == .workspaceMember(PackageIdentity.plain("app")))
    }

    /// Baseline: no explicit override and no focus yields the current
    /// default (`.allExcludingTests`). Ensures we don't regress the
    /// non-workspace case.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withNoFocusAndNoOverrides_returnsAllExcludingTests() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == .allExcludingTests())
    }

    /// Mutually-exclusive combinations (e.g. `--product` and `--target`
    /// both supplied) emit an error and return nil, regardless of
    /// focus.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withMutuallyExclusiveOverrides_returnsNilAndEmitsError() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: "app",
            target: "AppTarget",
            buildTests: false,
            workspaceMemberFocus: PackageIdentity.plain("app"),
            observabilityScope: observability.topScope,
        )

        #expect(subset == nil)
        #expect(!observability.diagnostics.isEmpty)
    }

    // MARK: - --package selector (Slice 5)

    /// `--package X` in a workspace that declares X yields
    /// `.workspaceMember(X)`. Baseline of the selector feature.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withValidSelectedPackage_returnsWorkspaceMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("lib-b"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                PackageIdentity.plain("app"),
                PackageIdentity.plain("lib-a"),
                PackageIdentity.plain("lib-b"),
            ],
            observabilityScope: observability.topScope,
        )

        #expect(subset == .workspaceMember(PackageIdentity.plain("lib-b")))
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package` overrides `currentWorkspaceMemberFocus` — the escape
    /// hatch for building a specific member from inside a different
    /// member's directory.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageAndDifferentFocus_selectedPackageWins() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("lib-b"),
            workspaceMemberFocus: PackageIdentity.plain("lib-a"),
            availableMemberIdentities: [
                PackageIdentity.plain("lib-a"),
                PackageIdentity.plain("lib-b"),
            ],
            observabilityScope: observability.topScope,
        )

        #expect(subset == .workspaceMember(PackageIdentity.plain("lib-b")))
    }

    /// `--package X` when X isn't a declared member: emit a diagnostic
    /// listing the known identities and return nil.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withUnknownSelectedPackage_returnsNilAndEmitsError() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [
            PackageIdentity.plain("app"),
            PackageIdentity.plain("lib-a"),
        ]

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("no-such"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: known,
            observabilityScope: observability.topScope,
        )

        #expect(subset == nil)

        let expected = Diagnostic.unknownWorkspaceMember(
            requested: PackageIdentity.plain("no-such"),
            known: known,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `--package X` outside a workspace (nil `availableMemberIdentities`):
    /// emit a "requires a Workspace.swift" diagnostic and return nil.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageOutsideWorkspace_returnsNilAndEmitsError() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == nil)

        let expected = Diagnostic.packageSelectorRequiresWorkspace(
            requested: PackageIdentity.plain("app"),
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `--package Y --product X` means "build product X within member Y".
    /// The explicit `--product` selector wins over the implicit member
    /// scoping; Swift Build resolves the product against the full
    /// workspace graph.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageAndProduct_returnsProduct() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: "AppExe",
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                PackageIdentity.plain("app"),
                PackageIdentity.plain("lib-a"),
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            subset == .product(
                "AppExe",
                for: nil,
                package: PackageIdentity.plain("app"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package Y --target Z` means "build target Z within member Y".
    /// Same composition rule as `--product`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageAndTarget_returnsTarget() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: "AppLib",
            buildTests: false,
            selectedPackage: PackageIdentity.plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                PackageIdentity.plain("app"),
                PackageIdentity.plain("lib-a"),
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            subset == .target(
                "AppLib",
                for: nil,
                package: PackageIdentity.plain("app"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package Y --build-tests` builds tests + non-tests scoped to
    /// member Y. The `.allIncludingTests` case carries the package
    /// identity so Swift Build's PIF routing can dispatch to a
    /// per-member test aggregate (Slice 6 wires the aggregate; Slice 5
    /// lands the plumbing).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageAndBuildTests_returnsAllIncludingTestsScopedToPackage() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: true,
            selectedPackage: PackageIdentity.plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: [
                PackageIdentity.plain("app"),
                PackageIdentity.plain("lib-a"),
            ],
            observabilityScope: observability.topScope,
        )

        #expect(
            subset == .allIncludingTests(
                package: PackageIdentity.plain("app"),
            ),
        )
        #expect(observability.diagnostics.isEmpty)
    }

    /// Sanity: `--build-tests` alone (no `--package`) still yields the
    /// workspace-wide `.allIncludingTests(package: nil)`. Locks in that
    /// the Slice 5 addition doesn't alter the non-workspace default.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withBuildTestsAndNoPackage_returnsWorkspaceWideAllIncludingTests() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: true,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == .allIncludingTests(package: nil))
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package Y` where Y matches the CWD-derived focus: the
    /// selector-driven identity still wins semantically, but the
    /// resulting subset is the same as focus-only. No error, no
    /// ambiguity.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageMatchingFocus_returnsWorkspaceMember() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: nil,
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("app"),
            workspaceMemberFocus: PackageIdentity.plain("app"),
            availableMemberIdentities: [
                PackageIdentity.plain("app"),
            ],
            observabilityScope: observability.topScope,
        )

        #expect(subset == .workspaceMember(PackageIdentity.plain("app")))
        #expect(observability.diagnostics.isEmpty)
    }

    /// Precedence: when `--package` is unknown AND `--product` is also
    /// supplied, the `--package` validation error surfaces first. This
    /// prevents the user from being confused by a downstream product-
    /// lookup failure when the real issue is the misspelled member
    /// identity.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withUnknownSelectedPackageAndProduct_reportsPackageErrorFirst() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [
            PackageIdentity.plain("app"),
            PackageIdentity.plain("lib-a"),
        ]

        let subset = BuildCommandOptions.computeBuildSubset(
            product: "AppExe",
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("no-such"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: known,
            observabilityScope: observability.topScope,
        )

        #expect(subset == nil)

        let expected = Diagnostic.unknownWorkspaceMember(
            requested: PackageIdentity.plain("no-such"),
            known: known,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// Precedence: when `--package` is supplied without a workspace AND
    /// `--product` is also supplied, the "requires a Workspace.swift"
    /// error surfaces first. Same rationale as
    /// `computeBuildSubset_withUnknownSelectedPackageAndProduct_reportsPackageErrorFirst`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeBuildSubset_withSelectedPackageOutsideWorkspaceAndProduct_reportsWorkspaceErrorFirst() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let subset = BuildCommandOptions.computeBuildSubset(
            product: "AppExe",
            target: nil,
            buildTests: false,
            selectedPackage: PackageIdentity.plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(subset == nil)

        let expected = Diagnostic.packageSelectorRequiresWorkspace(
            requested: PackageIdentity.plain("app"),
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }
}
