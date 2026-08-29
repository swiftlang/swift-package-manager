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
struct DumpPackageSelectionTests {
    /// `--package X` naming a valid member → dump only X.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func dumpPackage_selectedMember_withSelectedPackage_returnsIdentity() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = graph.rootPackages.map(\.manifest)

        let selected = DumpPackage.selectedMember(
            allRoots: allRoots,
            selectedPackage: .plain("app"),
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        let member = try #require(selected)
        #expect(member.packageIdentity == .plain("app"))
        #expect(observability.diagnostics.isEmpty)
    }

    /// CWD-inside-member → dump that member without an explicit
    /// `--package` flag.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func dumpPackage_selectedMember_withMemberFocus_returnsIdentity() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = graph.rootPackages.map(\.manifest)

        let selected = DumpPackage.selectedMember(
            allRoots: allRoots,
            selectedPackage: nil,
            workspaceMemberFocus: .plain("lib-a"),
            observabilityScope: observability.topScope,
        )

        let member = try #require(selected)
        #expect(member.packageIdentity == .plain("lib-a"))
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package Y` overrides CWD focus X — the explicit flag wins.
    /// Mirrors Slice 10's `ShowDependencies.scopedRootPackages` and
    /// Slice 13's `Describe.scopedRootPackages` precedence.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func dumpPackage_selectedMember_withBothSelectedAndMemberFocus_selectedWins() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = graph.rootPackages.map(\.manifest)

        let selected = DumpPackage.selectedMember(
            allRoots: allRoots,
            selectedPackage: .plain("app"),
            workspaceMemberFocus: .plain("lib-a"),
            observabilityScope: observability.topScope,
        )

        let member = try #require(selected)
        #expect(member.packageIdentity == .plain("app"))
    }

    /// `--package X` naming a non-member emits
    /// `.unknownWorkspaceMember` listing the known identities and
    /// returns nil so the caller can abort.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func dumpPackage_selectedMember_withUnknownSelectedPackage_emitsErrorAndReturnsNil() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = graph.rootPackages.map(\.manifest)
        let knownIdentities = Set(allRoots.map(\.packageIdentity))

        let selected = DumpPackage.selectedMember(
            allRoots: allRoots,
            selectedPackage: .plain("ghost"),
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(selected == nil)
        let expected = Basics.Diagnostic.unknownWorkspaceMember(
            requested: .plain("ghost"),
            known: knownIdentities,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// Single-root (non-workspace) invocation with no flag and no CWD
    /// focus → dump that root. Backwards-compat with pre-workspaces
    /// `swift package dump-package`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func dumpPackage_selectedMember_withSingleRoot_returnsIt() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.singleMemberGraph(observabilityScope: observability.topScope)
        let allRoots = graph.rootPackages.map(\.manifest)

        let selected = DumpPackage.selectedMember(
            allRoots: allRoots,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        let member = try #require(selected)
        #expect(member.packageIdentity == .plain("app"))
        #expect(observability.diagnostics.isEmpty)
    }

    /// Multi-root workspace root without `--package` and without CWD
    /// focus is ambiguous — `dump-package` emits exactly one manifest.
    /// Emit `.dumpPackageRequiresPackageSelector` listing known
    /// identities and return nil so the caller can abort.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func dumpPackage_selectedMember_withMultipleRootsAndNoSelection_emitsErrorAndReturnsNil() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try Self.twoMemberGraph(observabilityScope: observability.topScope)
        let allRoots = graph.rootPackages.map(\.manifest)
        let knownIdentities = Set(allRoots.map(\.packageIdentity))

        let selected = DumpPackage.selectedMember(
            allRoots: allRoots,
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            observabilityScope: observability.topScope,
        )

        #expect(selected == nil)
        let expected = Basics.Diagnostic.dumpPackageRequiresPackageSelector(
            known: knownIdentities,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    // MARK: - helpers

    /// Builds a two-member (`app` executable + `lib-a` library) graph.
    /// Mirrors `DescribeSubsetSelectionTests.twoMemberGraph`.
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

    /// Builds a one-member (`app`) graph — the pre-workspaces baseline.
    private static func singleMemberGraph(observabilityScope: ObservabilityScope) throws -> ModulesGraph {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/App/Sources/app/main.swift",
        ])
        let appManifest = Manifest.createRootManifest(
            displayName: "app",
            path: "/App",
            toolsVersion: .v5_3,
            products: [try .init(name: "app", type: .executable, targets: ["app"])],
            targets: [try .init(name: "app")],
        )
        return try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [appManifest],
            observabilityScope: observabilityScope,
        )
    }
}
