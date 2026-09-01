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

import struct TSCUtility.Version

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceResolveTests {
    // MARK: - Fixtures

    /// A two-member workspace: `lib-a` and `lib-b` at declared paths,
    /// with an optional list of workspace-level dependencies for the
    /// inherited-dependency tests.
    private static func makeWorkspaceManifest(
        dependencies: [PackageDependency] = [],
    ) -> WorkspaceManifest {
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
            dependencies: dependencies,
        )
    }

    /// A minimal `Manifest` for a member package with the given
    /// workspace-member dependency identities.
    private static func makeMemberManifest(
        name: String,
        workspaceMemberIdentities: [String],
    ) -> Manifest {
        let dependencies: [PackageDependency] = workspaceMemberIdentities.map { identity in
            .workspaceMember(
                PackageDependency.WorkspaceMember(
                    identity: PackageIdentity.plain(identity),
                    productFilter: .everything,
                    traits: nil,
                )
            )
        }
        return Self.makeMemberManifest(name: name, dependencies: dependencies)
    }

    /// A minimal `Manifest` for a member package with a caller-supplied
    /// dependency list. Used by tests that exercise mixed or workspace-
    /// inherited dependency kinds.
    private static func makeMemberManifest(
        name: String,
        dependencies: [PackageDependency],
    ) -> Manifest {
        let manifestPath = AbsolutePath("/repo/packages/\(name)/Package.swift")
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

    /// A workspace-level source-control dependency for use in
    /// `WorkspaceManifest.dependencies`.
    private static func sourceControlDep(
        identity: String,
        url: String,
        version: Version,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .sourceControl(
            identity: PackageIdentity.plain(identity),
            nameForTargetDependencyResolutionOnly: nil,
            location: .remote(SourceControlURL(url)),
            requirement: .range(version ..< Version(version.major + 1, 0, 0)),
            productFilter: .everything,
            traits: traits,
            registryIdentity: nil,
        )
    }

    /// A workspace-level registry dependency for use in
    /// `WorkspaceManifest.dependencies`.
    private static func registryDep(
        identity: String,
        version: Version,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .registry(
            identity: PackageIdentity.plain(identity),
            requirement: .range(version ..< Version(version.major + 1, 0, 0)),
            productFilter: .everything,
            traits: traits,
        )
    }

    /// A workspace-level file-system dependency for use in
    /// `WorkspaceManifest.dependencies`.
    private static func fileSystemDep(
        identity: String,
        path: AbsolutePath,
        traits: Set<PackageDependency.Trait>? = nil,
    ) -> PackageDependency {
        .fileSystem(
            identity: PackageIdentity.plain(identity),
            nameForTargetDependencyResolutionOnly: nil,
            path: path,
            productFilter: .everything,
            traits: traits,
        )
    }

    /// A member-level `.workspaceInherited` dependency for use in
    /// member `Manifest.dependencies`.
    private static func inheritedDep(
        identity: String,
        traits: Set<PackageDependency.Trait>? = nil,
        productFilter: ProductFilter = .everything,
    ) -> PackageDependency {
        .workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: PackageIdentity.plain(identity),
                productFilter: productFilter,
                traits: traits,
            )
        )
    }

    /// A member-level `.workspaceMember` dependency for use in member
    /// `Manifest.dependencies`. Mirrors `inheritedDep` but for the
    /// sibling-member case; the caller supplies the identity of the
    /// referenced workspace member and (optionally) a per-consumer
    /// trait set.
    private static func workspaceMemberDep(
        identity: String,
        traits: Set<PackageDependency.Trait>? = nil,
        productFilter: ProductFilter = .everything,
    ) -> PackageDependency {
        .workspaceMember(
            PackageDependency.WorkspaceMember(
                identity: PackageIdentity.plain(identity),
                productFilter: productFilter,
                traits: traits,
            )
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
                known: [PackageIdentity.plain("lib-a"), PackageIdentity.plain("lib-b")],
            ),
        ) {
            try PackageWorkspace.resolveWorkspaceMemberPaths(
                in: memberManifest,
                using: workspace,
            )
        }
    }

    /// The `unknownMember` error must surface a user-actionable
    /// description: the unknown identity, the manifest that
    /// referenced it, and the identities that ARE declared. Prior to
    /// the improved message the printed error was the opaque enum
    /// case string, which forced users to grep the source to figure
    /// out what went wrong.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func unknownMember_description_includesReferencedIdentityManifestAndKnown() throws {
        let error = WorkspaceResolveError.unknownMember(
            identity: PackageIdentity.plain("ghost"),
            manifestPath: AbsolutePath("/repo/packages/app/Package.swift"),
            known: [PackageIdentity.plain("lib-a"), PackageIdentity.plain("lib-b")],
        )

        let description = String(describing: error)

        #expect(description.contains("'ghost'"))
        #expect(description.contains("/repo/packages/app/Package.swift"))
        #expect(description.contains("'lib-a'"))
        #expect(description.contains("'lib-b'"))
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

    // MARK: - .workspaceInherited augment

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withKnownInheritedSourceControl_augmentsWithSourceControlResolution() throws {
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "swift-nio")],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited after augment, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.identity.description == "swift-nio")
        guard case .sourceControl(let location, _, _, _) = try #require(inherited.resolved) else {
            Issue.record("expected resolved .sourceControl, got: \(String(describing: inherited.resolved))")
            return
        }
        if case .remote(let url) = location {
            #expect(url.absoluteString == "https://github.com/apple/swift-nio")
        } else {
            Issue.record("expected remote location")
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withKnownInheritedRegistry_augmentsWithRegistryResolution() throws {
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.registryDep(identity: "scope.pkg", version: Version(1, 0, 0)),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "scope.pkg")],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited after augment, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.identity.description == "scope.pkg")
        guard case .registry = try #require(inherited.resolved) else {
            Issue.record("expected resolved .registry, got: \(String(describing: inherited.resolved))")
            return
        }
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withUnknownInherited_throwsUnknownInheritedDependency() throws {
        // Workspace declares swift-nio; member inherits "does-not-exist".
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "does-not-exist")],
        )

        #expect(
            throws: WorkspaceResolveError.unknownInheritedDependency(
                identity: PackageIdentity.plain("does-not-exist"),
                manifestPath: member.path,
                known: [PackageIdentity.plain("swift-nio")],
            ),
        ) {
            try PackageWorkspace.resolveWorkspaceMemberPaths(
                in: member,
                using: workspace,
            )
        }
    }

    /// The `unknownInheritedDependency` error must surface a user-
    /// actionable description: the unknown identity, the manifest
    /// that referenced it, and the workspace-level dependency
    /// identities that ARE declared. Same shape as
    /// `unknownMember`'s description.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func unknownInheritedDependency_description_includesReferencedIdentityManifestAndKnown() throws {
        let error = WorkspaceResolveError.unknownInheritedDependency(
            identity: PackageIdentity.plain("ghost"),
            manifestPath: AbsolutePath("/repo/packages/app/Package.swift"),
            known: [PackageIdentity.plain("some-lib"), PackageIdentity.plain("other-lib")],
        )

        let description = String(describing: error)

        #expect(description.contains("'ghost'"))
        #expect(description.contains("/repo/packages/app/Package.swift"))
        #expect(description.contains("'some-lib'"))
        #expect(description.contains("'other-lib'"))
    }

    /// When the `known` set is empty (workspace declares no members
    /// or no workspace-level deps yet), the description must not
    /// render an awkward empty list (`"…: "`). It emits a clear "no
    /// X are declared" phrase so the message stays actionable — the
    /// user sees they have zero declared entries, not a trailing
    /// colon.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func unknownMember_description_withEmptyKnown_saysNoneDeclared() throws {
        let error = WorkspaceResolveError.unknownMember(
            identity: PackageIdentity.plain("ghost"),
            manifestPath: AbsolutePath("/repo/packages/app/Package.swift"),
            known: [],
        )

        let description = String(describing: error)

        #expect(description.contains("'ghost'"))
        #expect(description.contains("no workspace members are declared in Workspace.swift"))
        // No trailing colon-then-nothing artifact from an empty list.
        #expect(description.contains(": \n") == false)
        #expect(description.hasSuffix(":") == false)
    }

    /// Parallel of the empty-known case for
    /// `unknownInheritedDependency`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func unknownInheritedDependency_description_withEmptyKnown_saysNoneDeclared() throws {
        let error = WorkspaceResolveError.unknownInheritedDependency(
            identity: PackageIdentity.plain("ghost"),
            manifestPath: AbsolutePath("/repo/packages/app/Package.swift"),
            known: [],
        )

        let description = String(describing: error)

        #expect(description.contains("'ghost'"))
        #expect(description.contains("no workspace-level dependencies are declared in Workspace.swift"))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withInheritedTraits_unionsWithWorkspaceTraits() throws {
        // Workspace declares dep with traits ["core"]; member inherits
        // with traits ["extras"]. Result should have both traits unioned
        // on the `.workspaceInherited` case.
        let workspaceTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "core"),
        ]
        let memberTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: workspaceTraits,
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: memberTraits),
            ],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited, got: \(resolved.dependencies[0])")
            return
        }
        let expectedTraits: Set<PackageDependency.Trait> = workspaceTraits.union(memberTraits)
        #expect(inherited.traits == expectedTraits)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withInheritedNilTraits_carriesWorkspaceTraits() throws {
        // Workspace declares traits; member inherits with no traits.
        // Result should carry the workspace's traits unchanged on the
        // `.workspaceInherited` case.
        let workspaceTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "core"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: workspaceTraits,
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "swift-nio")],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.traits == workspaceTraits)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func validateNoWorkspaceMemberDependencies_withWorkspaceInheritedDep_throws() throws {
        let manifest = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "swift-nio")],
        )

        #expect(
            throws: WorkspaceResolveError.workspaceInheritedUsedOutsideWorkspace(
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
    func resolveWorkspaceMemberPaths_withInheritedFileSystem_augmentsWithFileSystemResolution() throws {
        // Workspace declares a path-based dep; member inherits it. The
        // augmentation should produce a `.workspaceInherited` case whose
        // `resolved` carries the same absolute path.
        let externalPath = AbsolutePath("/repo/external/some-lib")
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.fileSystemDep(identity: "some-lib", path: externalPath),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "some-lib")],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited after augment, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.identity.description == "some-lib")
        guard case .fileSystem(let path, _) = try #require(inherited.resolved) else {
            Issue.record("expected resolved .fileSystem, got: \(String(describing: inherited.resolved))")
            return
        }
        #expect(path == externalPath)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withInheritedMemberTraitsOnly_carriesMemberTraits() throws {
        // Workspace declares dep with nil traits; member inherits with
        // traits ["extras"]. Result should carry the member's traits
        // unchanged on the `.workspaceInherited` case (the
        // `(inheritedTraits?, nil)` arm).
        let memberTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: memberTraits),
            ],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.traits == memberTraits)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withInheritedNoTraits_producesNilTraits() throws {
        // Neither workspace nor member specify traits. Result traits
        // on the augmented `.workspaceInherited` case should be nil
        // (the `(nil, nil)` arm).
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "swift-nio")],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.traits == nil)
    }

    /// Two members inherit the SAME workspace dep with DIFFERENT
    /// per-member `traits:` sets. Each member is resolved
    /// independently against the shared `WorkspaceManifest`. The
    /// per-member trait unions must not cross-contaminate: member A
    /// gets `workspace ∪ A`, member B gets `workspace ∪ B`, and
    /// neither sees the other's trait.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_multipleMembersInheritSameDepWithDifferentTraits_areIsolatedPerMember() throws {
        let workspaceTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "core"),
        ]
        let appTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let libATraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "perf"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: workspaceTraits,
            ),
        ])
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: appTraits),
            ],
        )
        let libAMember = Self.makeMemberManifest(
            name: "lib-a",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: libATraits),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibA = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libAMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibA.dependencies.count == 1)
        guard case .workspaceInherited(let appInherited) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceInherited, got: \(resolvedApp.dependencies[0])")
            return
        }
        guard case .workspaceInherited(let libAInherited) = resolvedLibA.dependencies[0] else {
            Issue.record("expected lib-a to have .workspaceInherited, got: \(resolvedLibA.dependencies[0])")
            return
        }

        #expect(appInherited.traits == workspaceTraits.union(appTraits))
        #expect(libAInherited.traits == workspaceTraits.union(libATraits))
        // Explicit cross-contamination guards: app must not have
        // lib-a's trait, and vice versa.
        #expect(appInherited.traits?.contains(PackageDependency.Trait(name: "perf")) == false)
        #expect(libAInherited.traits?.contains(PackageDependency.Trait(name: "extras")) == false)
    }

    /// Two members each inherit a DIFFERENT workspace-level dep.
    /// Each workspace dep declares its own trait set. Verifies that
    /// per-dep trait sets stay scoped to the correct dep: member
    /// "app"'s inherit of dep-A does not pick up dep-B's traits, and
    /// vice versa.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_multipleMembersInheritDifferentWorkspaceDeps_traitsScopedPerDep() throws {
        let netTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "net"),
        ]
        let logTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "log"),
        ]
        let appLayered: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "metrics"),
        ]
        let libALayered: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "trace"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: netTraits,
            ),
            Self.registryDep(
                identity: "log-lib",
                version: Version(1, 0, 0),
                traits: logTraits,
            ),
        ])
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: appLayered),
            ],
        )
        let libAMember = Self.makeMemberManifest(
            name: "lib-a",
            dependencies: [
                Self.inheritedDep(identity: "log-lib", traits: libALayered),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibA = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libAMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibA.dependencies.count == 1)
        guard case .workspaceInherited(let appInherited) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceInherited, got: \(resolvedApp.dependencies[0])")
            return
        }
        guard case .workspaceInherited(let libAInherited) = resolvedLibA.dependencies[0] else {
            Issue.record("expected lib-a to have .workspaceInherited, got: \(resolvedLibA.dependencies[0])")
            return
        }

        #expect(appInherited.identity.description == "swift-nio")
        #expect(appInherited.traits == netTraits.union(appLayered))
        #expect(appInherited.traits?.contains(PackageDependency.Trait(name: "log")) == false)
        #expect(appInherited.traits?.contains(PackageDependency.Trait(name: "trace")) == false)

        #expect(libAInherited.identity.description == "log-lib")
        #expect(libAInherited.traits == logTraits.union(libALayered))
        #expect(libAInherited.traits?.contains(PackageDependency.Trait(name: "net")) == false)
        #expect(libAInherited.traits?.contains(PackageDependency.Trait(name: "metrics")) == false)
    }

    /// Mixed nil-ness across members inheriting the same dep: one
    /// member inherits with nil (fall through to workspace's traits),
    /// the other layers additional traits on top. Isolation still
    /// holds — the nil-traits member must not accidentally acquire
    /// the layered member's traits.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_multipleMembersMixedInheritedNilTraits_areIsolatedPerMember() throws {
        let workspaceTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "core"),
        ]
        let libALayered: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: workspaceTraits,
            ),
        ])
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio"),
            ],
        )
        let libAMember = Self.makeMemberManifest(
            name: "lib-a",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: libALayered),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibA = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libAMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibA.dependencies.count == 1)
        guard case .workspaceInherited(let appInherited) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceInherited, got: \(resolvedApp.dependencies[0])")
            return
        }
        guard case .workspaceInherited(let libAInherited) = resolvedLibA.dependencies[0] else {
            Issue.record("expected lib-a to have .workspaceInherited, got: \(resolvedLibA.dependencies[0])")
            return
        }

        #expect(appInherited.traits == workspaceTraits)
        #expect(appInherited.traits?.contains(PackageDependency.Trait(name: "extras")) == false)
        #expect(libAInherited.traits == workspaceTraits.union(libALayered))
    }

    /// A workspace declares a trait-bearing dep. Only ONE member
    /// inherits it; the other member does not reference it at all.
    /// The non-inheriting member's dependency list must remain
    /// untouched — no accidental injection of the workspace dep or
    /// its traits into the non-inheriting member.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_onlyOneMemberInheritsTraitBearingDep_othersUnaffected() throws {
        let workspaceTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "core"),
        ]
        let appTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: workspaceTraits,
            ),
        ])
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", traits: appTraits),
            ],
        )
        // lib-a has NO inherited dep — only a workspace-member dep
        // to keep things realistic (a member with zero deps also
        // exercises the loop but is less interesting).
        let libAMember = Self.makeMemberManifest(
            name: "lib-a",
            workspaceMemberIdentities: ["lib-a"],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibA = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libAMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibA.dependencies.count == 1)
        guard case .workspaceInherited(let appInherited) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceInherited, got: \(resolvedApp.dependencies[0])")
            return
        }
        #expect(appInherited.traits == workspaceTraits.union(appTraits))

        // lib-a's single dependency must remain the workspace-member
        // dep (unchanged), NOT a smuggled-in .workspaceInherited for
        // swift-nio and NOT augmented with any workspace traits.
        guard case .workspaceMember(let libAOnlyDep) = resolvedLibA.dependencies[0] else {
            Issue.record("expected lib-a to have .workspaceMember, got: \(resolvedLibA.dependencies[0])")
            return
        }
        #expect(libAOnlyDep.identity.description == "lib-a")
        #expect(libAOnlyDep.traits == nil)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withInheritedPreservesMemberProductFilter() throws {
        // Workspace declares dep with `.everything` (workspaces are
        // roots); member narrows to `.specific(["Foo"])`. Result should
        // carry the member's `productFilter` on the outer
        // `.workspaceInherited` case, not the workspace's.
        let memberFilter: ProductFilter = .specific(["Foo"])
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.inheritedDep(identity: "swift-nio", productFilter: memberFilter),
            ],
        )

        let resolved = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: member,
            using: workspace,
        )

        try #require(resolved.dependencies.count == 1)
        guard case .workspaceInherited(let inherited) = resolved.dependencies[0] else {
            Issue.record("expected .workspaceInherited, got: \(resolved.dependencies[0])")
            return
        }
        #expect(inherited.productFilter == memberFilter)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_withMultipleMembersInheritingSameDep_augmentsIndependently() throws {
        // Two members inherit the same workspace-level dep with
        // different member-level trait sets. Each augmentation should
        // union the workspace's traits with only its own member's traits.
        let workspaceTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "core"),
        ]
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
                traits: workspaceTraits,
            ),
        ])

        let aTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "a-extras"),
        ]
        let bTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "b-extras"),
        ]
        let memberA = Self.makeMemberManifest(
            name: "lib-a",
            dependencies: [Self.inheritedDep(identity: "swift-nio", traits: aTraits)],
        )
        let memberB = Self.makeMemberManifest(
            name: "lib-b",
            dependencies: [Self.inheritedDep(identity: "swift-nio", traits: bTraits)],
        )

        let resolvedA = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: memberA,
            using: workspace,
        )
        let resolvedB = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: memberB,
            using: workspace,
        )

        try #require(resolvedA.dependencies.count == 1)
        try #require(resolvedB.dependencies.count == 1)
        guard case .workspaceInherited(let inheritedA) = resolvedA.dependencies[0] else {
            Issue.record("member A: expected .workspaceInherited")
            return
        }
        guard case .workspaceInherited(let inheritedB) = resolvedB.dependencies[0] else {
            Issue.record("member B: expected .workspaceInherited")
            return
        }
        #expect(inheritedA.traits == workspaceTraits.union(aTraits))
        #expect(inheritedB.traits == workspaceTraits.union(bTraits))
        // The two members' augmentations are truly independent: B's
        // traits should not leak into A's result, and vice-versa.
        #expect(inheritedA.traits?.contains(PackageDependency.Trait(name: "b-extras")) == false)
        #expect(inheritedB.traits?.contains(PackageDependency.Trait(name: "a-extras")) == false)
    }

    // MARK: - .workspaceMember trait isolation

    /// Two members both depend on the same sibling workspace member
    /// via `.package(workspaceMember:)` but with DIFFERENT per-member
    /// `traits:` sets. `resolveWorkspaceMemberPaths` preserves the
    /// authored traits verbatim (there is no workspace-level
    /// counterpart to union with, as there is for `.workspaceInherited`).
    /// Each member's resolved dep must carry its OWN trait set —
    /// no cross-contamination when both point at the same target.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_multipleMembersReferenceSameWorkspaceMemberWithDifferentTraits_areIsolatedPerMember() throws {
        let appTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let bTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "perf"),
        ]
        let workspace = Self.makeWorkspaceManifest()
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-a", traits: appTraits),
            ],
        )
        let libBMember = Self.makeMemberManifest(
            name: "lib-b",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-a", traits: bTraits),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibB = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libBMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibB.dependencies.count == 1)
        guard case .workspaceMember(let appDep) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceMember, got: \(resolvedApp.dependencies[0])")
            return
        }
        guard case .workspaceMember(let libBDep) = resolvedLibB.dependencies[0] else {
            Issue.record("expected lib-b to have .workspaceMember, got: \(resolvedLibB.dependencies[0])")
            return
        }

        #expect(appDep.traits == appTraits)
        #expect(libBDep.traits == bTraits)
        // Explicit cross-contamination guards: app must not have
        // lib-b's trait, and vice versa.
        #expect(appDep.traits?.contains(PackageDependency.Trait(name: "perf")) == false)
        #expect(libBDep.traits?.contains(PackageDependency.Trait(name: "extras")) == false)
    }

    /// Two members reference DIFFERENT sibling workspace members
    /// via `.package(workspaceMember:)`, each with its own per-consumer
    /// trait set. Verifies traits stay scoped to the correct target
    /// identity and don't bleed across `.workspaceMember` edges.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_multipleMembersReferenceDifferentWorkspaceMembersWithTraits_traitsScopedPerDep() throws {
        let appTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "app-flavor"),
        ]
        let consumerTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "consumer-flavor"),
        ]
        let workspace = Self.makeWorkspaceManifest()
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-a", traits: appTraits),
            ],
        )
        let consumerMember = Self.makeMemberManifest(
            name: "consumer",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-b", traits: consumerTraits),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedConsumer = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: consumerMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedConsumer.dependencies.count == 1)
        guard case .workspaceMember(let appDep) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceMember, got: \(resolvedApp.dependencies[0])")
            return
        }
        guard case .workspaceMember(let consumerDep) = resolvedConsumer.dependencies[0] else {
            Issue.record("expected consumer to have .workspaceMember, got: \(resolvedConsumer.dependencies[0])")
            return
        }

        #expect(appDep.identity.description == "lib-a")
        #expect(appDep.traits == appTraits)
        #expect(appDep.traits?.contains(PackageDependency.Trait(name: "consumer-flavor")) == false)

        #expect(consumerDep.identity.description == "lib-b")
        #expect(consumerDep.traits == consumerTraits)
        #expect(consumerDep.traits?.contains(PackageDependency.Trait(name: "app-flavor")) == false)
    }

    /// Mixed nil-ness across members referencing the same sibling
    /// workspace member: one member declares `traits: nil` on its
    /// `.package(workspaceMember:)`, the other declares an explicit
    /// trait set. The nil member's resolved dep must remain
    /// `traits: nil` — the other consumer's trait set must not leak
    /// into it. Verifies that `.workspaceMember` preserves the
    /// authored value verbatim (no accidental default injection).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_multipleMembersMixedWorkspaceMemberNilTraits_areIsolatedPerMember() throws {
        let libBTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let workspace = Self.makeWorkspaceManifest()
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-a"),
            ],
        )
        let libBMember = Self.makeMemberManifest(
            name: "lib-b",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-a", traits: libBTraits),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibB = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libBMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibB.dependencies.count == 1)
        guard case .workspaceMember(let appDep) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceMember, got: \(resolvedApp.dependencies[0])")
            return
        }
        guard case .workspaceMember(let libBDep) = resolvedLibB.dependencies[0] else {
            Issue.record("expected lib-b to have .workspaceMember, got: \(resolvedLibB.dependencies[0])")
            return
        }

        #expect(appDep.traits == nil)
        #expect(libBDep.traits == libBTraits)
    }

    /// A workspace declares two members; only ONE of them references
    /// a sibling workspace member via `.package(workspaceMember:)`
    /// with traits. The other member's dependency list is a
    /// non-workspace `.fileSystem` dep. Verifies the non-referencing
    /// member's dep list is preserved untouched — no traits leak from
    /// the referencing member, no `.workspaceMember` synthesized in
    /// its place.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func resolveWorkspaceMemberPaths_onlyOneMemberReferencesTraitBearingWorkspaceMember_othersUnaffected() throws {
        let appTraits: Set<PackageDependency.Trait> = [
            PackageDependency.Trait(name: "extras"),
        ]
        let externalPath = AbsolutePath("/repo/external/some-lib")
        let workspace = Self.makeWorkspaceManifest()
        let appMember = Self.makeMemberManifest(
            name: "app",
            dependencies: [
                Self.workspaceMemberDep(identity: "lib-a", traits: appTraits),
            ],
        )
        let libBMember = Self.makeMemberManifest(
            name: "lib-b",
            dependencies: [
                Self.fileSystemDep(identity: "some-lib", path: externalPath),
            ],
        )

        let resolvedApp = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: appMember,
            using: workspace,
        )
        let resolvedLibB = try PackageWorkspace.resolveWorkspaceMemberPaths(
            in: libBMember,
            using: workspace,
        )

        try #require(resolvedApp.dependencies.count == 1)
        try #require(resolvedLibB.dependencies.count == 1)
        guard case .workspaceMember(let appDep) = resolvedApp.dependencies[0] else {
            Issue.record("expected app to have .workspaceMember, got: \(resolvedApp.dependencies[0])")
            return
        }
        #expect(appDep.traits == appTraits)

        // lib-b's single dependency must remain the .fileSystem dep
        // unchanged — no smuggled-in .workspaceMember, no injected
        // traits from `app`.
        guard case .fileSystem(let libBOnlyDep) = resolvedLibB.dependencies[0] else {
            Issue.record("expected lib-b to have .fileSystem, got: \(resolvedLibB.dependencies[0])")
            return
        }
        #expect(libBOnlyDep.identity.description == "some-lib")
        #expect(libBOnlyDep.path == externalPath)
        #expect(libBOnlyDep.traits == nil)
    }

    // MARK: - unused workspace-dep audit

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findUnusedWorkspaceDependencies_whenAllDepsInherited_returnsEmpty() throws {
        // Two workspace deps, both inherited by at least one member.
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
            Self.registryDep(identity: "scope.pkg", version: Version(1, 0, 0)),
        ])
        let memberA = Self.makeMemberManifest(
            name: "lib-a",
            dependencies: [Self.inheritedDep(identity: "swift-nio")],
        )
        let memberB = Self.makeMemberManifest(
            name: "lib-b",
            dependencies: [Self.inheritedDep(identity: "scope.pkg")],
        )

        let unused = PackageWorkspace.findUnusedWorkspaceDependencies(
            workspace: workspace,
            memberManifests: [memberA, memberB],
        )

        #expect(unused.isEmpty)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findUnusedWorkspaceDependencies_whenSomeDepsNotInherited_returnsUnusedIdentities() throws {
        // Two workspace deps, only one inherited. The other should
        // surface in the unused list.
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "used",
                url: "https://github.com/example/used",
                version: Version(1, 0, 0),
            ),
            Self.sourceControlDep(
                identity: "unused",
                url: "https://github.com/example/unused",
                version: Version(1, 0, 0),
            ),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [Self.inheritedDep(identity: "used")],
        )

        let unused = PackageWorkspace.findUnusedWorkspaceDependencies(
            workspace: workspace,
            memberManifests: [member],
        )

        #expect(unused == [PackageIdentity.plain("unused")])
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findUnusedWorkspaceDependencies_whenNoMemberInheritsAny_returnsAllWorkspaceDeps() throws {
        // No member inherits any workspace dep. Every workspace dep
        // should be reported.
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "orphan-a",
                url: "https://github.com/example/orphan-a",
                version: Version(1, 0, 0),
            ),
            Self.registryDep(identity: "orphan-b", version: Version(1, 0, 0)),
        ])
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [],
        )

        let unused = PackageWorkspace.findUnusedWorkspaceDependencies(
            workspace: workspace,
            memberManifests: [member],
        )

        #expect(Set(unused) == Set([
            PackageIdentity.plain("orphan-a"),
            PackageIdentity.plain("orphan-b"),
        ]))
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findUnusedWorkspaceDependencies_whenMultipleMembersInheritSame_countsAsUsed() throws {
        // Two members both inherit the same workspace dep. It should not
        // appear in the unused list.
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "shared",
                url: "https://github.com/example/shared",
                version: Version(1, 0, 0),
            ),
        ])
        let memberA = Self.makeMemberManifest(
            name: "lib-a",
            dependencies: [Self.inheritedDep(identity: "shared")],
        )
        let memberB = Self.makeMemberManifest(
            name: "lib-b",
            dependencies: [Self.inheritedDep(identity: "shared")],
        )

        let unused = PackageWorkspace.findUnusedWorkspaceDependencies(
            workspace: workspace,
            memberManifests: [memberA, memberB],
        )

        #expect(unused.isEmpty)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findUnusedWorkspaceDependencies_ignoresNonInheritedMemberDeps() throws {
        // A member declares its own concrete `.fileSystem` dep with the
        // same identity as a workspace dep. That does NOT count as
        // "inheriting" — the workspace dep should still be reported as
        // unused.
        let workspace = Self.makeWorkspaceManifest(dependencies: [
            Self.sourceControlDep(
                identity: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                version: Version(2, 0, 0),
            ),
        ])
        let ownDep: PackageDependency = .fileSystem(
            identity: PackageIdentity.plain("swift-nio"),
            nameForTargetDependencyResolutionOnly: nil,
            path: AbsolutePath("/repo/vendored/swift-nio"),
            productFilter: .everything,
            traits: nil,
        )
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [ownDep],
        )

        let unused = PackageWorkspace.findUnusedWorkspaceDependencies(
            workspace: workspace,
            memberManifests: [member],
        )

        #expect(unused == [PackageIdentity.plain("swift-nio")])
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func findUnusedWorkspaceDependencies_whenWorkspaceHasNoDeps_returnsEmpty() throws {
        // Trivial case: no workspace deps means nothing can be unused.
        let workspace = Self.makeWorkspaceManifest()
        let member = Self.makeMemberManifest(
            name: "app",
            dependencies: [],
        )

        let unused = PackageWorkspace.findUnusedWorkspaceDependencies(
            workspace: workspace,
            memberManifests: [member],
        )

        #expect(unused.isEmpty)
    }
}
