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

        #expect(subset == .allIncludingTests)
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

        #expect(subset == .allIncludingTests)
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

        #expect(subset == .allExcludingTests)
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
}
