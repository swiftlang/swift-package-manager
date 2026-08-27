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
@testable import Workspace

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceOriginHashTests {
    // MARK: - computeResolvedFileOriginHash (Slice 8e)

    /// Passing `nil` for both workspace-scope inputs preserves the
    /// pre-workspace hash payload — concatenated manifest contents
    /// followed by root-dep location strings. This is the regression
    /// guard for single-package invocations: the moment
    /// `computeResolvedFileOriginHash` gains workspace-aware
    /// branches, non-workspace loads must still see the historical
    /// hash.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withoutWorkspaceManifest_matchesLegacyPayload() throws {
        let manifestContents = ["// Package.swift for lib-a\n"]
        let dependencyLocations = ["https://example.com/dep-a"]
        let expected = (manifestContents.joined() + dependencyLocations.joined()).sha256Checksum

        let actual = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: nil,
            workspaceOverridesContent: nil,
        )

        #expect(actual == expected)
    }

    /// A `Workspace.swift` file that is present but happens to be
    /// empty contributes nothing to the hash payload — same as the
    /// `nil` (no workspace at all) case. Confirms the append-if-non-
    /// nil branch is a pure passthrough for empty content.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withEmptyWorkspaceManifestContent_matchesNilBranch() throws {
        let manifestContents = ["// Package.swift for lib-a\n"]
        let dependencyLocations = ["https://example.com/dep-a"]

        let withNil = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: nil,
            workspaceOverridesContent: nil,
        )
        let withEmpty = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: "",
            workspaceOverridesContent: nil,
        )

        #expect(withNil == withEmpty)
    }

    /// Providing a non-empty `Workspace.swift` content to an
    /// otherwise identical hash payload changes the hash. This is
    /// the whole point of feeding Workspace.swift into the payload:
    /// any edit to the workspace manifest — new dep, member list
    /// change, `ignoredStateDirectories` toggle, even a comment —
    /// must invalidate the resolved-file cache.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withWorkspaceManifestContent_differsFromNil() throws {
        let manifestContents = ["// Package.swift for lib-a\n"]
        let dependencyLocations = ["https://example.com/dep-a"]

        let withoutWorkspace = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: nil,
            workspaceOverridesContent: nil,
        )
        let withWorkspace = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: "// Workspace.swift with one dep\n",
            workspaceOverridesContent: nil,
        )

        #expect(withoutWorkspace != withWorkspace)
    }

    /// Two workspaces differing only in their `Workspace.swift`
    /// contents produce different hashes. Covers the primary
    /// use case: user edits Workspace.swift (e.g., adds a
    /// workspace-level dep), resolution should be invalidated.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withDifferentWorkspaceManifestContent_produceDifferentHashes() throws {
        let manifestContents = ["// Package.swift for lib-a\n"]
        let dependencyLocations: [String] = []

        let hashA = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: "workspace: [alpha]",
            workspaceOverridesContent: nil,
        )
        let hashB = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: "workspace: [alpha, beta]",
            workspaceOverridesContent: nil,
        )

        #expect(hashA != hashB)
    }

    /// Providing a non-empty overrides file content to an otherwise
    /// identical hash payload changes the hash. Adding or removing
    /// `.swiftpm/configuration/workspace-overrides.json` must
    /// invalidate the resolved-file cache so SwiftPM re-resolves
    /// with the current override set.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withWorkspaceOverridesContent_differsFromNil() throws {
        let manifestContents = ["// Package.swift for lib-a\n"]
        let dependencyLocations: [String] = []
        let workspaceManifestContent = "// Workspace.swift\n"

        let withoutOverrides = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: workspaceManifestContent,
            workspaceOverridesContent: nil,
        )
        let withOverrides = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: workspaceManifestContent,
            workspaceOverridesContent: #"{"version":1,"overrides":[]}"#,
        )

        #expect(withoutOverrides != withOverrides)
    }

    /// Two workspaces differing only in their overrides file
    /// contents produce different hashes. Covers the developer
    /// workflow: editing `.swiftpm/configuration/workspace-overrides.json`
    /// (adding, removing, or retargeting an override) forces a
    /// fresh resolution.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withDifferentWorkspaceOverridesContent_produceDifferentHashes() throws {
        let manifestContents = ["// Package.swift for lib-a\n"]
        let dependencyLocations: [String] = []
        let workspaceManifestContent = "// Workspace.swift\n"

        let hashA = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: workspaceManifestContent,
            workspaceOverridesContent: #"{"version":1,"overrides":[{"identity":"alpha","kind":{"fileSystem":{"name":null,"path":"a"}}}]}"#,
        )
        let hashB = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: workspaceManifestContent,
            workspaceOverridesContent: #"{"version":1,"overrides":[{"identity":"alpha","kind":{"fileSystem":{"name":null,"path":"b"}}}]}"#,
        )

        #expect(hashA != hashB)
    }

    /// The hash is deterministic — same inputs, same output, across
    /// invocations. Guards against nondeterminism creeping in via a
    /// mutable data structure or an unsorted set iteration.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func withSameInputs_isDeterministic() throws {
        let manifestContents = ["// Package.swift for lib-a\n", "// Package.swift for lib-b\n"]
        let dependencyLocations = ["https://example.com/root-dep"]
        let workspaceManifestContent = "// Workspace.swift\nlet workspace = Workspace(...)\n"
        let workspaceOverridesContent = #"{"version":1,"overrides":[]}"#

        let hash1 = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: workspaceManifestContent,
            workspaceOverridesContent: workspaceOverridesContent,
        )
        let hash2 = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: manifestContents,
            dependencyLocations: dependencyLocations,
            workspaceManifestContent: workspaceManifestContent,
            workspaceOverridesContent: workspaceOverridesContent,
        )

        #expect(hash1 == hash2)
    }

    // MARK: - resolvedFileOriginHash (wiring integration)

    /// Two `PackageGraphRootInput`s that point at the same member
    /// `Package.swift` but at different `Workspace.swift` files on
    /// disk must produce different origin hashes. This is the
    /// integration seam between `PackageGraphRootInput` and the pure
    /// hash payload builder — it verifies that
    /// `root.workspaceManifest?.path` is actually read from disk and
    /// fed into the payload, which the pure
    /// `computeResolvedFileOriginHash` unit tests cannot catch on
    /// their own.
    ///
    /// Reading the file on every call also decouples the hash from
    /// the manifest-loader's parsed-value cache: even if a second
    /// resolve reused a stale `WorkspaceManifest.dependencies`, the
    /// on-disk file bytes would still be current.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func resolvedFileOriginHash_withDifferentWorkspaceManifestFiles_producesDifferentHashes() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending("app")
        let workspaceManifestPath = workspaceRoot.appending("Workspace.swift")
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(memberPath, recursive: true)
        try fileSystem.writeFileContents(
            memberPath.appending("Package.swift"),
            string: "// swift-tools-version: 999.0\nimport PackageDescription\nlet package = Package(name: \"app\")\n",
        )

        let manifestModel = WorkspaceManifest(
            path: workspaceManifestPath,
            toolsVersion: .current,
            members: [],
            dependencies: [],
        )
        let root = PackageGraphRootInput(
            packages: [memberPath],
            workspaceManifest: manifestModel,
        )

        try fileSystem.writeFileContents(
            workspaceManifestPath,
            string: "// Workspace.swift version A\n",
        )
        let hashA = try PackageWorkspace.resolvedFileOriginHash(
            root: root,
            fileSystem: fileSystem,
            currentToolsVersion: .current,
        )
        try fileSystem.writeFileContents(
            workspaceManifestPath,
            string: "// Workspace.swift version B\n",
        )
        let hashB = try PackageWorkspace.resolvedFileOriginHash(
            root: root,
            fileSystem: fileSystem,
            currentToolsVersion: .current,
        )

        #expect(
            hashA != hashB,
            "editing Workspace.swift must change the origin hash; got \(hashA) both times",
        )
    }

    /// Two invocations against the same workspace root but with
    /// different `.swiftpm/configuration/workspace-overrides.json`
    /// contents on disk must produce different origin hashes. Locks
    /// in the wiring that reads the overrides file into the payload
    /// — without this, adding or editing an override would silently
    /// skip re-resolution.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func resolvedFileOriginHash_withDifferentWorkspaceOverridesFiles_producesDifferentHashes() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let memberPath = workspaceRoot.appending("app")
        let workspaceManifestPath = workspaceRoot.appending("Workspace.swift")
        let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
            forRootPackage: workspaceRoot,
        )
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(memberPath, recursive: true)
        try fileSystem.writeFileContents(
            memberPath.appending("Package.swift"),
            string: "// swift-tools-version: 999.0\nimport PackageDescription\nlet package = Package(name: \"app\")\n",
        )
        try fileSystem.writeFileContents(
            workspaceManifestPath,
            string: "// Workspace.swift\n",
        )
        try fileSystem.createDirectory(overridesFile.parentDirectory, recursive: true)

        let root = PackageGraphRootInput(
            packages: [memberPath],
            workspaceManifest: WorkspaceManifest(
                path: workspaceManifestPath,
                toolsVersion: .current,
                members: [],
                dependencies: [],
            ),
        )

        try fileSystem.writeFileContents(
            overridesFile,
            string: #"{"version":1,"overrides":[{"identity":"alpha","kind":{"fileSystem":{"name":null,"path":"a"}}}]}"#,
        )
        let hashA = try PackageWorkspace.resolvedFileOriginHash(
            root: root,
            fileSystem: fileSystem,
            currentToolsVersion: .current,
        )
        try fileSystem.writeFileContents(
            overridesFile,
            string: #"{"version":1,"overrides":[{"identity":"alpha","kind":{"fileSystem":{"name":null,"path":"b"}}}]}"#,
        )
        let hashB = try PackageWorkspace.resolvedFileOriginHash(
            root: root,
            fileSystem: fileSystem,
            currentToolsVersion: .current,
        )

        #expect(
            hashA != hashB,
            "editing the workspace-overrides file must change the origin hash; got \(hashA) both times",
        )
    }

    /// A `PackageGraphRootInput` with `workspaceManifest == nil`
    /// produces the same hash as the pure helper's `nil` branch —
    /// the wiring must not spuriously synthesize a workspace-manifest
    /// contribution when there is no workspace manifest.
    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func resolvedFileOriginHash_withoutWorkspaceManifest_matchesPureHelperNilBranch() throws {
        let memberPath = AbsolutePath("/repo/app")
        let manifestBody = "// swift-tools-version: 999.0\nimport PackageDescription\nlet package = Package(name: \"app\")\n"
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(memberPath, recursive: true)
        try fileSystem.writeFileContents(memberPath.appending("Package.swift"), string: manifestBody)

        let root = PackageGraphRootInput(packages: [memberPath])
        let actual = try PackageWorkspace.resolvedFileOriginHash(
            root: root,
            fileSystem: fileSystem,
            currentToolsVersion: .current,
        )
        let expected = PackageWorkspace.computeResolvedFileOriginHash(
            manifestContents: [manifestBody],
            dependencyLocations: [],
            workspaceManifestContent: nil,
            workspaceOverridesContent: nil,
        )

        #expect(actual == expected)
    }
}
