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
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph
import PackageModel
import Testing
import _InternalTestSupport

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct DescribeSubsetSelectionTests {
    /// No `--package`, no CWD focus → describe every in-scope member.
    /// Returns the full root list unchanged.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func describe_scopedRootPackages_withoutAnyFocus_returnsAll() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = Array(graph.rootPackages)

        let scoped = SwiftPackageCommand.Describe.scopedRootPackages(
            allRoots: allRoots,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        try #require(scoped != nil)
        #expect(Set(scoped!.map(\.identity)) == Set(allRoots.map(\.identity)))
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package X` naming a valid member → describe only X.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func describe_scopedRootPackages_withSelectedPackage_returnsIdentity() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = Array(graph.rootPackages)

        let scoped = SwiftPackageCommand.Describe.scopedRootPackages(
            allRoots: allRoots,
            selectedPackage: .plain("app"),
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        try #require(scoped != nil)
        #expect(scoped!.map(\.identity) == [.plain("app")])
        #expect(observability.diagnostics.isEmpty)
    }

    /// CWD-inside-member → describe only that member. No `--package`
    /// needed.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func describe_scopedRootPackages_withMemberFocus_returnsIdentity() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = Array(graph.rootPackages)

        let scoped = SwiftPackageCommand.Describe.scopedRootPackages(
            allRoots: allRoots,
            selectedPackage: nil,
            workspaceMemberFocus: .plain("liba"),
            observabilityScope: observability.topScope,
        )

        try #require(scoped != nil)
        #expect(scoped!.map(\.identity) == [.plain("liba")])
    }

    /// `--package Y` overrides CWD focus X — the explicit flag wins.
    /// Mirrors Slice 5's `computeBuildSubset` and Slice 10's
    /// `ShowDependencies.scopedRootPackages` precedence.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func describe_scopedRootPackages_withBothSelectedAndMemberFocus_selectedWins() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = Array(graph.rootPackages)

        let scoped = SwiftPackageCommand.Describe.scopedRootPackages(
            allRoots: allRoots,
            selectedPackage: .plain("app"),
            workspaceMemberFocus: .plain("liba"),
            observabilityScope: observability.topScope,
        )

        try #require(scoped != nil)
        #expect(scoped!.map(\.identity) == [.plain("app")])
    }

    /// `--package X` naming a non-member emits
    /// `.unknownWorkspaceMember` listing the known identities and
    /// returns nil so the caller can abort.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func describe_scopedRootPackages_withUnknownSelectedPackage_emitsErrorAndReturnsNil() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = Array(graph.rootPackages)
        let knownIdentities = Set(allRoots.map(\.identity))

        let scoped = SwiftPackageCommand.Describe.scopedRootPackages(
            allRoots: allRoots,
            selectedPackage: .plain("ghost"),
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(scoped == nil)
        let expected = Basics.Diagnostic.unknownWorkspaceMember(
            requested: .plain("ghost"),
            known: knownIdentities,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    // MARK: - helpers

    /// Builds a two-member (`app` executable + `lib-a` library) graph
    /// via `loadModulesGraph` — same pattern used by
    /// `UpdateSubsetSelectionTests` and `PackageCommandTests`. No
    /// external deps; both members are self-contained roots.
    private static func twoMemberGraph(observabilityScope: ObservabilityScope) throws -> ModulesGraph {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/App/Sources/app/main.swift",
            "/LibA/Sources/LibA/LibA.swift",
        ])
        let appManifest = Manifest.createRootManifest(
            displayName: "app",
            path: "/App",
            toolsVersion: .v5_3,
            products: [try .init(name: "app", type: .executable, targets: ["app"])],
            targets: [try .init(name: "app")],
        )
        let libAManifest = Manifest.createRootManifest(
            displayName: "lib-a",
            path: "/LibA",
            toolsVersion: .v5_3,
            products: [try .init(name: "LibA", type: .library(.automatic), targets: ["LibA"])],
            targets: [try .init(name: "LibA")],
        )
        return try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [appManifest, libAManifest],
            observabilityScope: observabilityScope,
        )
    }
}
