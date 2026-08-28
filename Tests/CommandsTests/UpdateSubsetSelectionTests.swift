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
struct UpdateSubsetSelectionTests {
    // MARK: - computeUpdateFocus

    /// No `--package`, no CWD focus, no workspace context → the update
    /// covers every workspace-level dep. Decision fn returns nil.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeUpdateFocus_withoutAnyFocus_returnsNil() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let focus = SwiftPackageCommand.Update.computeUpdateFocus(
            selectedPackage: nil,
            workspaceMemberFocus: nil,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(focus == nil)
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package X` naming a valid member → focus is X.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeUpdateFocus_withSelectedPackage_returnsIdentity() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [.plain("app"), .plain("lib-a")]

        let focus = SwiftPackageCommand.Update.computeUpdateFocus(
            selectedPackage: .plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: known,
            observabilityScope: observability.topScope,
        )

        #expect(focus == .plain("app"))
        #expect(observability.diagnostics.isEmpty)
    }

    /// CWD-inside-member (Slice 4) → focus is the enclosing member's
    /// identity, no `--package` needed.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeUpdateFocus_withMemberFocus_returnsIdentity() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [.plain("app"), .plain("lib-a")]

        let focus = SwiftPackageCommand.Update.computeUpdateFocus(
            selectedPackage: nil,
            workspaceMemberFocus: .plain("lib-a"),
            availableMemberIdentities: known,
            observabilityScope: observability.topScope,
        )

        #expect(focus == .plain("lib-a"))
        #expect(observability.diagnostics.isEmpty)
    }

    /// `--package X` overrides a CWD focus on Y — the explicit flag
    /// wins. Mirrors Slice 5's precedence in `computeBuildSubset`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeUpdateFocus_withBothSelectedAndMemberFocus_selectedWins() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [.plain("app"), .plain("lib-a")]

        let focus = SwiftPackageCommand.Update.computeUpdateFocus(
            selectedPackage: .plain("app"),
            workspaceMemberFocus: .plain("lib-a"),
            availableMemberIdentities: known,
            observabilityScope: observability.topScope,
        )

        #expect(focus == .plain("app"))
    }

    /// `--package X` outside a workspace (`availableMemberIdentities`
    /// is nil): emit `.packageSelectorRequiresWorkspace` and return
    /// nil so the command runner can halt.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeUpdateFocus_withSelectedPackageOutsideWorkspace_emitsErrorAndReturnsNil() throws {
        let observability = ObservabilitySystem.makeForTesting()

        let focus = SwiftPackageCommand.Update.computeUpdateFocus(
            selectedPackage: .plain("app"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: nil,
            observabilityScope: observability.topScope,
        )

        #expect(focus == nil)
        let expected = Basics.Diagnostic.packageSelectorRequiresWorkspace(
            requested: .plain("app"),
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    /// `--package X` naming a non-member: emit `.unknownWorkspaceMember`
    /// listing the known identities and return nil.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeUpdateFocus_withUnknownSelectedPackage_emitsErrorAndReturnsNil() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let known: Set<PackageIdentity> = [.plain("app"), .plain("lib-a")]

        let focus = SwiftPackageCommand.Update.computeUpdateFocus(
            selectedPackage: .plain("ghost"),
            workspaceMemberFocus: nil,
            availableMemberIdentities: known,
            observabilityScope: observability.topScope,
        )

        #expect(focus == nil)
        let expected = Basics.Diagnostic.unknownWorkspaceMember(
            requested: .plain("ghost"),
            known: known,
        )
        let actual = try #require(observability.diagnostics.first)
        #expect(actual.severity == expected.severity)
        #expect(actual.message == expected.message)
    }

    // MARK: - computeTransitiveDepIdentities

    /// A member with no package-level dependencies yields an empty
    /// transitive-dep set. Locks in the base case for the graph walk.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeTransitiveDepIdentities_withNoDeps_returnsEmpty() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/RootTarget/main.swift",
        ])
        let manifestRoot = Manifest.createRootManifest(
            displayName: "Root",
            path: "/Root",
            toolsVersion: .v5_3,
            products: [try .init(name: "exe", type: .executable, targets: ["RootTarget"])],
            targets: [try .init(name: "RootTarget")],
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [manifestRoot],
            observabilityScope: observability.topScope,
        )
        expectNoDiagnostics(observability.diagnostics)

        let identities = SwiftPackageCommand.Update.computeTransitiveDepIdentities(
            memberIdentity: .plain("root"),
            graph: graph,
        )

        #expect(identities.isEmpty)
    }

    /// A member with direct file-system deps returns each dep's
    /// identity. One level of the walk.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeTransitiveDepIdentities_withDirectDeps_returnsThose() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/RootTarget/main.swift",
            "/DepA/Sources/DepA/A.swift",
        ])
        let manifestRoot = Manifest.createRootManifest(
            displayName: "Root",
            path: "/Root",
            toolsVersion: .v5_3,
            dependencies: [.fileSystem(path: "/DepA")],
            products: [try .init(name: "exe", type: .executable, targets: ["RootTarget"])],
            targets: [try .init(name: "RootTarget", dependencies: ["DepA"])],
        )
        let manifestDepA = Manifest.createFileSystemManifest(
            displayName: "DepA",
            path: "/DepA",
            toolsVersion: .v5_3,
            products: [try .init(name: "DepA", type: .library(.dynamic), targets: ["DepA"])],
            targets: [try .init(name: "DepA")],
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [manifestRoot, manifestDepA],
            observabilityScope: observability.topScope,
        )
        expectNoDiagnostics(observability.diagnostics)

        let identities = SwiftPackageCommand.Update.computeTransitiveDepIdentities(
            memberIdentity: .plain("root"),
            graph: graph,
        )

        let expected: Set<PackageIdentity> = [.plain("depa")]
        #expect(identities == expected)
    }

    /// A member depending on A → A depending on B yields both A and
    /// B when queried from the member. Locks in the recursive walk.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeTransitiveDepIdentities_withTransitiveDeps_returnsAll() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/RootTarget/main.swift",
            "/DepA/Sources/DepA/A.swift",
            "/DepB/Sources/DepB/B.swift",
        ])
        let manifestRoot = Manifest.createRootManifest(
            displayName: "Root",
            path: "/Root",
            toolsVersion: .v5_3,
            dependencies: [.fileSystem(path: "/DepA")],
            products: [try .init(name: "exe", type: .executable, targets: ["RootTarget"])],
            targets: [try .init(name: "RootTarget", dependencies: ["DepA"])],
        )
        let manifestDepA = Manifest.createFileSystemManifest(
            displayName: "DepA",
            path: "/DepA",
            toolsVersion: .v5_3,
            dependencies: [.fileSystem(path: "/DepB")],
            products: [try .init(name: "DepA", type: .library(.dynamic), targets: ["DepA"])],
            targets: [try .init(name: "DepA", dependencies: ["DepB"])],
        )
        let manifestDepB = Manifest.createFileSystemManifest(
            displayName: "DepB",
            path: "/DepB",
            toolsVersion: .v5_3,
            products: [try .init(name: "DepB", type: .library(.dynamic), targets: ["DepB"])],
            targets: [try .init(name: "DepB")],
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [manifestRoot, manifestDepA, manifestDepB],
            observabilityScope: observability.topScope,
        )
        expectNoDiagnostics(observability.diagnostics)

        let identities = SwiftPackageCommand.Update.computeTransitiveDepIdentities(
            memberIdentity: .plain("root"),
            graph: graph,
        )

        let expected: Set<PackageIdentity> = [.plain("depa"), .plain("depb")]
        #expect(identities == expected)
    }

    /// Diamond dependency (Root → {A, B}; A → D; B → D) resolves to
    /// {A, B, D} — D appears once. Locks in the visited-set dedup so
    /// the transitive walk doesn't emit D twice.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func computeTransitiveDepIdentities_withDiamond_dedups() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/RootTarget/main.swift",
            "/DepA/Sources/DepA/A.swift",
            "/DepB/Sources/DepB/B.swift",
            "/DepD/Sources/DepD/D.swift",
        ])
        let manifestRoot = Manifest.createRootManifest(
            displayName: "Root",
            path: "/Root",
            toolsVersion: .v5_3,
            dependencies: [
                .fileSystem(path: "/DepA"),
                .fileSystem(path: "/DepB"),
            ],
            products: [try .init(name: "exe", type: .executable, targets: ["RootTarget"])],
            targets: [try .init(name: "RootTarget", dependencies: ["DepA", "DepB"])],
        )
        let manifestDepA = Manifest.createFileSystemManifest(
            displayName: "DepA",
            path: "/DepA",
            toolsVersion: .v5_3,
            dependencies: [.fileSystem(path: "/DepD")],
            products: [try .init(name: "DepA", type: .library(.dynamic), targets: ["DepA"])],
            targets: [try .init(name: "DepA", dependencies: ["DepD"])],
        )
        let manifestDepB = Manifest.createFileSystemManifest(
            displayName: "DepB",
            path: "/DepB",
            toolsVersion: .v5_3,
            dependencies: [.fileSystem(path: "/DepD")],
            products: [try .init(name: "DepB", type: .library(.dynamic), targets: ["DepB"])],
            targets: [try .init(name: "DepB", dependencies: ["DepD"])],
        )
        let manifestDepD = Manifest.createFileSystemManifest(
            displayName: "DepD",
            path: "/DepD",
            toolsVersion: .v5_3,
            products: [try .init(name: "DepD", type: .library(.dynamic), targets: ["DepD"])],
            targets: [try .init(name: "DepD")],
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [manifestRoot, manifestDepA, manifestDepB, manifestDepD],
            observabilityScope: observability.topScope,
        )
        expectNoDiagnostics(observability.diagnostics)

        let identities = SwiftPackageCommand.Update.computeTransitiveDepIdentities(
            memberIdentity: .plain("root"),
            graph: graph,
        )

        let expected: Set<PackageIdentity> = [.plain("depa"), .plain("depb"), .plain("depd")]
        #expect(identities == expected)
    }
}
