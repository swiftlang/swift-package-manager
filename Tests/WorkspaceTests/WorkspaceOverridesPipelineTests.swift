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
import PackageGraph
import PackageLoading
import PackageModel
import Testing
import Workspace
import _InternalTestSupport

import struct TSCUtility.Version

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceOverridesPipelineTests {

    // MARK: - loadRootManifests pipeline tests

    /// Verifies that when `loadRootManifests` is called with an override whose
    /// identity matches a dep declared in a MEMBER's `Package.swift` (absent from
    /// workspace-level dependencies), the returned manifest for that member has
    /// the dep rewritten to the override's `.fileSystem` kind.
    ///
    /// This is the primary pipeline integration test for Cycle 11: it proves
    /// the `overrides:` parameter flows all the way from `loadRootManifests`
    /// through the per-member `apply(_:to:)` call and back out in the returned
    /// `[AbsolutePath: Manifest]` dictionary.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func loadRootManifests_withOverrideTargetingMemberDep_rewritesMemberManifestDep() async throws {
        // Arrange: in-memory FS rooted at /repo; member "app" at /repo/packages/app.
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending(components: "packages", "app")
        let localExtLibPath = workspaceRoot.appending(components: "external", "local-ext-lib")

        try fs.createDirectory(memberPath, recursive: true)
        try fs.writeFileContents(
            memberPath.appending("Package.swift"),
            string: "// swift-tools-version:999.0\n",
        )

        // Member declares a .sourceControl dep on "ext-lib"; workspace has no dep on it.
        let memberManifest = Manifest.createRootManifest(
            displayName: "app",
            path: memberPath,
            toolsVersion: .vNext,
            dependencies: [
                .sourceControl(
                    identity: PackageIdentity.plain("ext-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    location: .remote(SourceControlURL("https://example.com/ext-lib")),
                    requirement: .range(Version(1, 0, 0)..<Version(2, 0, 0)),
                    productFilter: .everything,
                    traits: nil,
                    registryIdentity: nil,
                ),
            ],
        )

        // Workspace-level manifest has no dep on "ext-lib".
        let workspaceManifest = WorkspaceManifest(
            path: workspaceRoot.appending(WorkspaceManifest.filename),
            toolsVersion: .vNext,
            members: [
                WorkspaceManifest.Member(
                    identity: PackageIdentity.plain("app"),
                    path: memberPath,
                ),
            ],
            dependencies: [],
        )

        // Override redirects "ext-lib" from the remote URL to a local .fileSystem path.
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("ext-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("ext-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: localExtLibPath,
                productFilter: .everything,
                traits: nil,
            ),
        )

        let mockLoader = MockManifestLoader(
            manifests: [
                MockManifestLoader.Key(url: memberPath.pathString): memberManifest,
            ],
        )

        let workspace = try PackageWorkspace._init(
            fileSystem: fs,
            environment: .mockEnvironment,
            location: .init(forRootPackage: workspaceRoot, fileSystem: fs),
            customHostToolchain: .mockHostToolchain(fs),
            customManifestLoader: mockLoader,
        )

        // Act.
        let result = try await workspace.loadRootManifests(
            packages: [memberPath],
            workspaceManifest: workspaceManifest,
            overrides: [override],
            observabilityScope: ObservabilitySystem.NOOP,
        )

        // Assert: the member manifest's dep is rewritten to .fileSystem pointing at
        // the local override path.
        let loaded = try #require(
            result[memberPath],
            "expected manifest for member at \(memberPath), got keys: \(result.keys)",
        )
        #expect(loaded.dependencies.count == 1)
        let dep = try #require(
            loaded.dependencies.first,
            "expected at least one dep in rewritten member manifest",
        )
        guard case .fileSystem(let settings) = dep else {
            Issue.record("expected .fileSystem dep, got \(dep)")
            return
        }
        #expect(settings.path == localExtLibPath)
    }

    /// Verifies that when `loadRootManifests` is called with an override
    /// targeting an identity absent from both the workspace manifest and all
    /// member manifests, it throws
    /// `WorkspaceOverridesApplyError.unknownIdentity("ghost-lib")`.
    ///
    /// This test pins the pipeline end-to-end behaviour of the `validate`
    /// call that `loadRootManifests` must perform after loading all member
    /// manifests (Cycle 11 insertion point ~line 1190 in `Workspace.swift`).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func loadRootManifests_withOverrideForAbsentIdentity_throwsUnknownIdentity() async throws {
        // Arrange: same scaffold as the rewrite test, but override targets "ghost-lib"
        // which is not declared anywhere.
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending(components: "packages", "app")

        try fs.createDirectory(memberPath, recursive: true)
        try fs.writeFileContents(
            memberPath.appending("Package.swift"),
            string: "// swift-tools-version:999.0\n",
        )

        // Member declares a dep on "known-lib"; workspace has no deps.
        let memberManifest = Manifest.createRootManifest(
            displayName: "app",
            path: memberPath,
            toolsVersion: .vNext,
            dependencies: [
                .fileSystem(
                    identity: PackageIdentity.plain("known-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: workspaceRoot.appending(components: "external", "known-lib"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ],
        )

        let workspaceManifest = WorkspaceManifest(
            path: workspaceRoot.appending(WorkspaceManifest.filename),
            toolsVersion: .vNext,
            members: [
                WorkspaceManifest.Member(
                    identity: PackageIdentity.plain("app"),
                    path: memberPath,
                ),
            ],
            dependencies: [],
        )

        // Override targets "ghost-lib" — absent from workspace and all members.
        let ghostOverride = WorkspaceOverridesJSONParser.Override(
            identity: .plain("ghost-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("ghost-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: workspaceRoot.appending(components: "external", "ghost"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let mockLoader = MockManifestLoader(
            manifests: [
                MockManifestLoader.Key(url: memberPath.pathString): memberManifest,
            ],
        )

        let workspace = try PackageWorkspace._init(
            fileSystem: fs,
            environment: .mockEnvironment,
            location: .init(forRootPackage: workspaceRoot, fileSystem: fs),
            customHostToolchain: .mockHostToolchain(fs),
            customManifestLoader: mockLoader,
        )

        // Act + Assert: validate fires after all manifests are loaded and throws
        // unknownIdentity for "ghost-lib".
        await #expect(throws: WorkspaceOverridesApplyError.unknownIdentity("ghost-lib")) {
            _ = try await workspace.loadRootManifests(
                packages: [memberPath],
                workspaceManifest: workspaceManifest,
                overrides: [ghostOverride],
                observabilityScope: ObservabilitySystem.NOOP,
            )
        }
    }

    // MARK: - loadPackageGraph pipeline tests

    /// Verifies that `Workspace.loadPackageGraph(rootInput:)` forwards
    /// `rootInput.overrides` into its internal `loadRootManifests` call so the
    /// per-member `apply(_:to:)` step and the cross-scope `validate` step both
    /// fire on the real production path (as exercised by `swift build`,
    /// `swift resolve`, etc.).
    ///
    /// The assertion vehicle is the `validate`-thrown
    /// `WorkspaceOverridesApplyError.unknownIdentity` for a ghost identity:
    /// this throw can *only* occur if `rootInput.overrides` reaches
    /// `loadRootManifests`. Asserting the rewrite through the returned
    /// `ModulesGraph` is prohibitively awkward here (the graph load requires
    /// a full resolver, Package.resolved, and repository provider machinery
    /// beyond this pipeline test's scope), so we prove the wiring via the
    /// validate-error surface — the same surface the second
    /// `loadRootManifests_...` test pins one layer down.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func loadPackageGraph_withOverrideForAbsentIdentity_propagatesUnknownIdentity() async throws {
        // Arrange: same scaffold as the ghost-identity loadRootManifests test.
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending(components: "packages", "app")

        try fs.createDirectory(memberPath, recursive: true)
        try fs.writeFileContents(
            memberPath.appending("Package.swift"),
            string: "// swift-tools-version:999.0\n",
        )

        let memberManifest = Manifest.createRootManifest(
            displayName: "app",
            path: memberPath,
            toolsVersion: .vNext,
            dependencies: [
                .fileSystem(
                    identity: PackageIdentity.plain("known-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: workspaceRoot.appending(components: "external", "known-lib"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ],
        )

        let workspaceManifest = WorkspaceManifest(
            path: workspaceRoot.appending(WorkspaceManifest.filename),
            toolsVersion: .vNext,
            members: [
                WorkspaceManifest.Member(
                    identity: PackageIdentity.plain("app"),
                    path: memberPath,
                ),
            ],
            dependencies: [],
        )

        let ghostOverride = WorkspaceOverridesJSONParser.Override(
            identity: .plain("ghost-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("ghost-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: workspaceRoot.appending(components: "external", "ghost"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let mockLoader = MockManifestLoader(
            manifests: [
                MockManifestLoader.Key(url: memberPath.pathString): memberManifest,
            ],
        )

        let workspace = try PackageWorkspace._init(
            fileSystem: fs,
            environment: .mockEnvironment,
            location: .init(forRootPackage: workspaceRoot, fileSystem: fs),
            customHostToolchain: .mockHostToolchain(fs),
            customManifestLoader: mockLoader,
        )

        // rootInput carries the workspace manifest and the ghost override; the
        // production-path wiring under test is that `loadPackageGraph(rootInput:)`
        // must forward `rootInput.overrides` into the internal
        // `loadRootManifests(...)` call so `validate` fires.
        let rootInput = PackageGraphRootInput(
            packages: [memberPath],
            workspaceManifest: workspaceManifest,
            overrides: [ghostOverride],
        )

        // Act + Assert: the pipeline must surface unknownIdentity for "ghost-lib".
        // Pre-wiring (bug): `loadPackageGraph` drops `rootInput.overrides` on the
        // floor, `validate` never runs, and this throw never fires.
        await #expect(throws: WorkspaceOverridesApplyError.unknownIdentity("ghost-lib")) {
            _ = try await workspace.loadPackageGraph(
                rootInput: rootInput,
                observabilityScope: ObservabilitySystem.NOOP,
            )
        }
    }
}
