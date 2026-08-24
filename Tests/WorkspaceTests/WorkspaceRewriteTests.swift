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
import PackageModel
import Testing
import Workspace

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceRewriteTests {
    // MARK: - Fixtures

    /// A two-member workspace: `lib-a` and `lib-b` at declared paths.
    private static func makeWorkspaceManifest() -> WorkspaceManifest {
        let workspaceRoot = AbsolutePath("/repo")
        return WorkspaceManifest(
            path: workspaceRoot.appending(WorkspaceManifest.filename),
            toolsVersion: .vNext,
            members: [
                WorkspaceManifest.Member(
                    identity: PackageIdentity.plain("lib-a"),
                    path: workspaceRoot.appending(components: "packages", "lib-a"),
                ),
                WorkspaceManifest.Member(
                    identity: PackageIdentity.plain("lib-b"),
                    path: workspaceRoot.appending(components: "packages", "lib-b"),
                ),
            ],
            dependencies: [],
        )
    }

    /// A minimal `Manifest` for a member package with the given
    /// workspace-member dependency identities.
    private static func makeMemberManifest(
        name: String,
        workspaceMemberIdentities: [String],
    ) -> Manifest {
        let manifestPath = AbsolutePath("/repo/packages/\(name)/Package.swift")
        let dependencies: [PackageDependency] = workspaceMemberIdentities.map { identity in
            .workspaceMember(
                PackageDependency.WorkspaceMember(
                    identity: PackageIdentity.plain(identity),
                    productFilter: .everything,
                    traits: nil,
                )
            )
        }
        return Manifest(
            displayName: name,
            packageIdentity: PackageIdentity.plain(name),
            path: manifestPath,
            packageKind: .root(manifestPath.parentDirectory),
            packageLocation: manifestPath.parentDirectory.pathString,
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
            dependencies: dependencies,
            products: [],
            targets: [],
            traits: [],
        )
    }

    // MARK: - Tests

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withKnownMember_populatesPath() throws {
        let workspace = Self.makeWorkspaceManifest()
        let memberManifest = Self.makeMemberManifest(
            name: "app",
            workspaceMemberIdentities: ["lib-a"],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: memberManifest,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        let dep = resolved.dependencies[0]
        guard case .workspaceMember(let member) = dep else {
            Issue.record("expected .workspaceMember after resolve, got: \(dep)")
            return
        }
        #expect(member.identity.description == "lib-a")
        #expect(member.path == AbsolutePath("/repo/packages/lib-a"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withUnknownMember_throwsUnknownMember() throws {
        let workspace = Self.makeWorkspaceManifest()
        let memberManifest = Self.makeMemberManifest(
            name: "app",
            workspaceMemberIdentities: ["does-not-exist"],
        )

        #expect(
            throws: WorkspaceResolveError.unknownMember(
                identity: PackageIdentity.plain("does-not-exist"),
                manifestPath: memberManifest.path,
            ),
        ) {
            try PackageWorkspace.resolveWorkspaceMemberPaths(
                in: memberManifest,
                using: workspace,
            )
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_leavesNonWorkspaceDepsUnchanged() throws {
        let workspace = Self.makeWorkspaceManifest()
        let manifestPath = AbsolutePath("/repo/packages/app/Package.swift")
        let externalDep: PackageDependency = .fileSystem(
            identity: PackageIdentity.plain("external"),
            nameForTargetDependencyResolutionOnly: nil,
            path: AbsolutePath("/some/other/place"),
            productFilter: .everything,
            traits: nil,
        )
        let manifest = Manifest(
            displayName: "app",
            packageIdentity: PackageIdentity.plain("app"),
            path: manifestPath,
            packageKind: .root(manifestPath.parentDirectory),
            packageLocation: manifestPath.parentDirectory.pathString,
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
            dependencies: [externalDep],
            products: [],
            targets: [],
            traits: [],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: manifest,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .fileSystem(let settings) = resolved.dependencies[0] else {
            Issue.record("dep kind changed unexpectedly")
            return
        }
        #expect(settings.identity.description == "external")
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func validateNoWorkspaceMemberDependencies_withWorkspaceMemberDep_throws() throws {
        let manifest = Self.makeMemberManifest(
            name: "app",
            workspaceMemberIdentities: ["lib-a"],
        )

        #expect(
            throws: WorkspaceResolveError.workspaceMemberUsedOutsideWorkspace(
                manifestPath: manifest.path,
            ),
        ) {
            try PackageWorkspace.validateNoWorkspaceMemberDependencies(in: manifest)
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func validateNoWorkspaceMemberDependencies_withOnlyRegularDeps_returns() throws {
        let manifestPath = AbsolutePath("/repo/packages/app/Package.swift")
        let externalDep: PackageDependency = .fileSystem(
            identity: PackageIdentity.plain("external"),
            nameForTargetDependencyResolutionOnly: nil,
            path: AbsolutePath("/some/other/place"),
            productFilter: .everything,
            traits: nil,
        )
        let manifest = Manifest(
            displayName: "app",
            packageIdentity: PackageIdentity.plain("app"),
            path: manifestPath,
            packageKind: .root(manifestPath.parentDirectory),
            packageLocation: manifestPath.parentDirectory.pathString,
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
            dependencies: [externalDep],
            products: [],
            targets: [],
            traits: [],
        )

        // Should not throw.
        try PackageWorkspace.validateNoWorkspaceMemberDependencies(in: manifest)
    }
}
