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
struct FileSystemPackageContainerWorkspaceTests {
    /// When a `PackageWorkspace` is operating in workspaces mode and a
    /// `FileSystemPackageContainer` is created for a workspace member,
    /// the container must apply the workspace's member/inherited-dep
    /// resolution to the manifest it loads. Otherwise `.workspaceInherited`
    /// deps reach `packageRef` with a nil `resolved` field, which
    /// `preconditionFailure`s.
    ///
    /// Under the Slice 3 augmentation contract the `.workspaceInherited`
    /// case is preserved (not rewritten to concrete) and its `resolved`
    /// payload is populated with the workspace's concrete-source
    /// declaration. This test pins that contract at the container level.
    @Test(
        .tags(
            Tag.TestSize.medium,
        ),
    )
    func fileSystemContainer_forWorkspaceMember_augmentsInheritedDep() async throws {
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending(components: "packages", "app")
        let externalPath = workspaceRoot.appending(components: "external", "some-lib")
        let memberManifestPath = memberPath.appending("Package.swift")

        try fs.createDirectory(memberPath, recursive: true)
        try fs.writeFileContents(
            memberManifestPath,
            string: "// swift-tools-version:999.0\n",
        )

        let memberManifest = Manifest(
            displayName: "app",
            packageIdentity: PackageIdentity.plain("app"),
            path: memberManifestPath,
            packageKind: .fileSystem(memberPath),
            packageLocation: memberPath.pathString,
            defaultLocalization: nil,
            platforms: [],
            version: nil,
            revision: nil,
            toolsVersion: .vNext,
            pkgConfig: nil,
            providers: nil,
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil,
            dependencies: [
                .workspaceInherited(
                    PackageDependency.WorkspaceInherited(
                        identity: PackageIdentity.plain("some-lib"),
                        productFilter: .everything,
                        traits: [PackageDependency.Trait(name: "default")],
                    )
                ),
            ],
            products: [],
            targets: [],
            traits: [],
        )

        let mockLoader = MockManifestLoader(
            manifests: [
                MockManifestLoader.Key(url: memberPath.pathString): memberManifest,
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
            dependencies: [
                .fileSystem(
                    identity: PackageIdentity.plain("some-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: externalPath,
                    productFilter: .everything,
                    traits: nil,
                ),
            ],
        )

        let provider = try PackageWorkspace._init(
            fileSystem: fs,
            environment: .mockEnvironment,
            location: .init(forRootPackage: workspaceRoot, fileSystem: fs),
            customHostToolchain: .mockHostToolchain(fs),
            customManifestLoader: mockLoader,
        )
        // Simulate what `loadRootManifests(packages:workspaceManifest:...)`
        // does at the top of a workspace-mode graph-load pass.
        provider.workspaceManifest = workspaceManifest

        let memberRef = PackageReference(
            identity: PackageIdentity.plain("app"),
            kind: .fileSystem(memberPath),
        )
        let container = try await provider.getContainer(
            for: memberRef,
            updateStrategy: .never,
            observabilityScope: ObservabilitySystem.NOOP,
        )

        let fsContainer = try #require(
            container as? FileSystemPackageContainer,
            "expected FileSystemPackageContainer for a .fileSystem package kind, got: \(type(of: container))",
        )

        let loaded = try await fsContainer.loadedManifestForTesting()

        // Under the augmentation contract, exactly one dep remains and
        // it stays as `.workspaceInherited` — but with `resolved`
        // populated from the workspace's `some-lib` declaration.
        try #require(loaded.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = loaded.dependencies[0] else {
            Issue.record(
                "expected .workspaceInherited (augmented) after container-level resolve, got: \(loaded.dependencies[0])",
            )
            return
        }
        #expect(inherited.identity == PackageIdentity.plain("some-lib"))
        guard case .fileSystem(let path, _) = try #require(inherited.resolved) else {
            Issue.record(
                "expected resolved .fileSystem, got: \(String(describing: inherited.resolved))",
            )
            return
        }
        #expect(path == externalPath)
    }
}
