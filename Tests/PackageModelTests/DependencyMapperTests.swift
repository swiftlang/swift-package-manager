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
@testable import PackageModel
import Testing

import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import enum TSCBasic.FileMode
import struct TSCBasic.FileSystemError
import struct TSCUtility.Version

struct DependencyMapperTests {
    private let parentPath = try! Basics.AbsolutePath(validating: "/parent")

    private func mappedFileSystemPath(
        _ path: String,
        fileSystem: FileSystem
    ) throws -> Basics.AbsolutePath {
        let mapper = DefaultDependencyMapper(identityResolver: DefaultIdentityResolver())
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .fileSystem(name: nil, path: path),
            productFilter: .everything,
            traits: nil
        )
        let mapped = try mapper.mappedDependency(dependency, fileSystem: fileSystem)
        guard case .fileSystem(let settings) = mapped else {
            Issue.record("expected fileSystem-kind dependency, got \(mapped)")
            throw FileSystemError(.unsupported)
        }
        return settings.path
    }

    @Test
    func tildePathIsExpandedAgainstHomeDirectory() throws {
        // InMemoryFileSystem provides a synthetic home at /home/user — the
        // happy path that should keep working after the regression fix.
        let resolved = try mappedFileSystemPath("~/Library/Stuff", fileSystem: InMemoryFileSystem())
        #expect(resolved == (try Basics.AbsolutePath(validating: "/home/user/Library/Stuff")))
    }

    @Test
    func tildePathThrowsInsteadOfCrashingWhenHomeDirectoryUnsupported() {
        // Regression test for rdar://177668882: a remote source-control
        // package whose manifest contains `.package(path: "~/...")` previously
        // crashed Xcode because the underlying GitFileSystemView's
        // `homeDirectory` aborted with `fatalError` instead of throwing. Make
        // sure the dependency mapper now produces an actionable error.
        #expect {
            try mappedFileSystemPath(
                "~/Documents/games/BoardGameKitHost",
                fileSystem: ThrowingHomeDirectoryFileSystem()
            )
        } throws: { error in
            let description = String(describing: error)
            return description.contains("~/") && description.contains("BoardGameKitHost")
        }
    }

    @Test
    func absolutePathIsLeftAlone() throws {
        let resolved = try mappedFileSystemPath("/absolute/path", fileSystem: InMemoryFileSystem())
        #expect(resolved == (try Basics.AbsolutePath(validating: "/absolute/path")))
    }

    @Test
    func relativePathIsResolvedAgainstParent() throws {
        let resolved = try mappedFileSystemPath("Sibling", fileSystem: InMemoryFileSystem())
        #expect(resolved == parentPath.appending(component: "Sibling"))
    }

    /// A `.workspaceInherited` `PackageDependency` whose `resolved` field
    /// has already been populated (Slice 3 augmentation) must survive a
    /// projection to `MappablePackageDependency` and back. Prior to the
    /// fix, `MappablePackageDependency.Kind.workspaceInherited` only
    /// carried the identity string — round-tripping through the mapper
    /// (as the graph does for mirror rewrites, path normalization, etc.)
    /// dropped `resolved`, and downstream `packageRef` then hit a
    /// `preconditionFailure` on the nil field.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedRoundTripPreservesResolvedField() throws {
        let externalPath = try Basics.AbsolutePath(validating: "/repo/external/some-lib")
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .specific(["LibB"]),
            traits: [PackageDependency.Trait(name: "default")],
            resolved: .fileSystem(path: externalPath, nameForTargetDependencyResolutionOnly: nil),
        )
        let original: PackageDependency = .workspaceInherited(expected)

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")

        guard case .workspaceInherited(let inherited) = roundTripped else {
            Issue.record("expected .workspaceInherited after round-trip, got: \(roundTripped)")
            return
        }
        #expect(inherited == expected)
    }

    /// A `.workspaceInherited` `PackageDependency` with `resolved == nil`
    /// (parse-time state, before workspace load augments it) must round-
    /// trip as nil — the mapper doesn't invent a resolution.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedRoundTripPreservesNilResolvedField() throws {
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .everything,
            traits: nil,
            resolved: nil,
        )
        let original: PackageDependency = .workspaceInherited(expected)

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")

        guard case .workspaceInherited(let inherited) = roundTripped else {
            Issue.record("expected .workspaceInherited after round-trip, got: \(roundTripped)")
            return
        }
        #expect(inherited == expected)
    }

    /// A `.workspaceMember` `PackageDependency` whose `path` field has
    /// been populated by `PackageWorkspace.resolveWorkspaceMemberPaths`
    /// (Slice 2 augmentation) must survive a projection to
    /// `MappablePackageDependency` and back. Prior to the fix,
    /// `MappablePackageDependency.Kind.workspaceMember` only carried
    /// the identity string — the graph's mapper round-trip dropped
    /// `path`, and `packageRef` then hit a `preconditionFailure`.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceMemberRoundTripPreservesPathField() throws {
        let memberPath = try Basics.AbsolutePath(validating: "/repo/packages/lib-a")
        let expected = PackageDependency.WorkspaceMember(
            identity: .plain("lib-a"),
            path: memberPath,
            productFilter: .specific(["LibB"]),
            traits: [PackageDependency.Trait(name: "default")],
        )
        let original: PackageDependency = .workspaceMember(expected)

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")

        guard case .workspaceMember(let member) = roundTripped else {
            Issue.record("expected .workspaceMember after round-trip, got: \(roundTripped)")
            return
        }
        #expect(member == expected)
    }

    /// A `.workspaceMember` `PackageDependency` with `path == nil`
    /// (parse-time state, before workspace load populates it) must
    /// round-trip as nil.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceMemberRoundTripPreservesNilPathField() throws {
        let expected = PackageDependency.WorkspaceMember(
            identity: .plain("lib-a"),
            productFilter: .everything,
            traits: nil,
        )
        let original: PackageDependency = .workspaceMember(expected)

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")

        guard case .workspaceMember(let member) = roundTripped else {
            Issue.record("expected .workspaceMember after round-trip, got: \(roundTripped)")
            return
        }
        #expect(member == expected)
    }

    /// `PackageDependency.filtered(by:)` on a `.workspaceMember` must
    /// preserve the `path` field so that a productFilter propagated
    /// during graph pruning doesn't strip it. Prior to the fix, the
    /// `filtered(by:)` implementation constructed a fresh
    /// `WorkspaceMember` without threading `settings.path`.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceMemberFilteredByProductFilterPreservesPath() throws {
        let memberPath = try Basics.AbsolutePath(validating: "/repo/packages/lib-a")
        let original: PackageDependency = .workspaceMember(
            PackageDependency.WorkspaceMember(
                identity: .plain("lib-a"),
                path: memberPath,
                productFilter: .everything,
                traits: nil,
            )
        )
        let expected = PackageDependency.WorkspaceMember(
            identity: .plain("lib-a"),
            path: memberPath,
            productFilter: .specific(["LibB"]),
            traits: nil,
        )

        let filtered = original.filtered(by: .specific(["LibB"]))
        guard case .workspaceMember(let member) = filtered else {
            Issue.record("expected .workspaceMember after filtered(by:), got: \(filtered)")
            return
        }
        #expect(member == expected)
    }

    /// `PackageDependency.filtered(by:)` on a `.workspaceInherited` must
    /// preserve the augmented `resolved` field. The Slice 3 augmentation
    /// contract expects the concrete workspace source to survive filter
    /// propagation just like the Slice 2 `.workspaceMember` case.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedFilteredByProductFilterPreservesResolved() throws {
        let externalPath = try Basics.AbsolutePath(validating: "/repo/external/some-lib")
        let resolved: PackageDependency.WorkspaceInherited.ResolvedInherited =
            .fileSystem(path: externalPath, nameForTargetDependencyResolutionOnly: nil)
        let original: PackageDependency = .workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: .plain("some-lib"),
                productFilter: .everything,
                traits: nil,
                resolved: resolved,
            )
        )
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .specific(["LibB"]),
            traits: nil,
            resolved: resolved,
        )

        let filtered = original.filtered(by: .specific(["LibB"]))
        guard case .workspaceInherited(let inherited) = filtered else {
            Issue.record("expected .workspaceInherited after filtered(by:), got: \(filtered)")
            return
        }
        #expect(inherited == expected)
    }

    // MARK: - Coverage: all ResolvedInherited variants

    /// Round-trip preserves a `.sourceControl` `ResolvedInherited` payload
    /// (location, requirement, name-for-target-dep-resolution, registryIdentity).
    /// Guards against a future field addition on the source-control variant
    /// silently dropping through the mapper.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedRoundTripPreservesSourceControlResolved() throws {
        let url = SourceControlURL("https://github.com/apple/swift-nio")
        let requirement: PackageDependency.SourceControl.Requirement = .range(Version(2, 0, 0) ..< Version(3, 0, 0))
        let registryIdentity = PackageIdentity.plain("apple.swift-nio")
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("swift-nio"),
            productFilter: .everything,
            traits: nil,
            resolved: .sourceControl(
                location: .remote(url),
                requirement: requirement,
                nameForTargetDependencyResolutionOnly: "swift-nio-name",
                registryIdentity: registryIdentity,
            ),
        )
        let original: PackageDependency = .workspaceInherited(expected)

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")

        guard case .workspaceInherited(let inherited) = roundTripped else {
            Issue.record("expected .workspaceInherited after round-trip, got: \(roundTripped)")
            return
        }
        #expect(inherited == expected)
    }

    /// Round-trip preserves a `.registry` `ResolvedInherited` payload.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedRoundTripPreservesRegistryResolved() throws {
        let requirement: PackageDependency.Registry.Requirement = .exact(Version(1, 2, 3))
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("scope.pkg"),
            productFilter: .everything,
            traits: nil,
            resolved: .registry(requirement: requirement),
        )
        let original: PackageDependency = .workspaceInherited(expected)

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")

        guard case .workspaceInherited(let inherited) = roundTripped else {
            Issue.record("expected .workspaceInherited after round-trip, got: \(roundTripped)")
            return
        }
        #expect(inherited == expected)
    }

    // MARK: - Coverage: public DefaultDependencyMapper.mappedDependency

    /// `DefaultDependencyMapper.mappedDependency` — the public entry point
    /// production uses — must preserve `WorkspaceMember.path` through its
    /// normalization + mirror-substitution pipeline, not just the raw
    /// `PackageDependency(_ seed: MappablePackageDependency, ...)` init.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceMemberMappedDependencyPreservesPath() throws {
        let memberPath = try Basics.AbsolutePath(validating: "/repo/packages/lib-a")
        let expected = PackageDependency.WorkspaceMember(
            identity: .plain("lib-a"),
            path: memberPath,
            productFilter: .everything,
            traits: nil,
        )
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .workspaceMember(expected),
            productFilter: .everything,
            traits: nil,
        )

        let mapper = DefaultDependencyMapper(identityResolver: DefaultIdentityResolver())
        let mapped = try mapper.mappedDependency(dependency, fileSystem: InMemoryFileSystem())

        guard case .workspaceMember(let member) = mapped else {
            Issue.record("expected .workspaceMember from mappedDependency, got: \(mapped)")
            return
        }
        #expect(member == expected)
    }

    /// `DefaultDependencyMapper.mappedDependency` must preserve
    /// `WorkspaceInherited.resolved` through its pipeline.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedMappedDependencyPreservesResolved() throws {
        let externalPath = try Basics.AbsolutePath(validating: "/repo/external/some-lib")
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .everything,
            traits: nil,
            resolved: .fileSystem(path: externalPath, nameForTargetDependencyResolutionOnly: nil),
        )
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .workspaceInherited(expected),
            productFilter: .everything,
            traits: nil,
        )

        let mapper = DefaultDependencyMapper(identityResolver: DefaultIdentityResolver())
        let mapped = try mapper.mappedDependency(dependency, fileSystem: InMemoryFileSystem())

        guard case .workspaceInherited(let inherited) = mapped else {
            Issue.record("expected .workspaceInherited from mappedDependency, got: \(mapped)")
            return
        }
        #expect(inherited == expected)
    }

    // MARK: - Coverage: composed roundtrip + filter

    /// Round-trip through the mapper AND then `.filtered(by:)`. Both
    /// operations preserve augmentation individually (asserted above);
    /// this checks the composed pipeline in the order production
    /// invokes it (mapper first, then filter propagation) so an
    /// order-dependent regression can't slip past unit coverage.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceMemberRoundTripThenFilterPreservesPath() throws {
        let memberPath = try Basics.AbsolutePath(validating: "/repo/packages/lib-a")
        let original: PackageDependency = .workspaceMember(
            PackageDependency.WorkspaceMember(
                identity: .plain("lib-a"),
                path: memberPath,
                productFilter: .everything,
                traits: nil,
            )
        )
        let expected = PackageDependency.WorkspaceMember(
            identity: .plain("lib-a"),
            path: memberPath,
            productFilter: .specific(["LibB"]),
            traits: nil,
        )

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")
        let filtered = roundTripped.filtered(by: .specific(["LibB"]))

        guard case .workspaceMember(let member) = filtered else {
            Issue.record("expected .workspaceMember after round-trip + filter, got: \(filtered)")
            return
        }
        #expect(member == expected)
    }

    /// Round-trip through the mapper AND then `.filtered(by:)` for
    /// `.workspaceInherited`.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInheritedRoundTripThenFilterPreservesResolved() throws {
        let externalPath = try Basics.AbsolutePath(validating: "/repo/external/some-lib")
        let resolved: PackageDependency.WorkspaceInherited.ResolvedInherited =
            .fileSystem(path: externalPath, nameForTargetDependencyResolutionOnly: nil)
        let original: PackageDependency = .workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: .plain("some-lib"),
                productFilter: .everything,
                traits: nil,
                resolved: resolved,
            )
        )
        let expected = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .specific(["LibB"]),
            traits: nil,
            resolved: resolved,
        )

        let mappable = MappablePackageDependency(original, parentPackagePath: parentPath)
        let roundTripped = try PackageDependency(mappable, newLocationString: "")
        let filtered = roundTripped.filtered(by: .specific(["LibB"]))

        guard case .workspaceInherited(let inherited) = filtered else {
            Issue.record("expected .workspaceInherited after round-trip + filter, got: \(filtered)")
            return
        }
        #expect(inherited == expected)
    }

    /// A `.workspaceInherited` dependency whose `resolved` field
    /// points at a remote source-control URL must have that URL
    /// mirror-substituted by `DefaultDependencyMapper` just like a
    /// plain `.package(url:)` declared in a `Package.swift` — the
    /// invariant Sam K stated: "preserve the same behaviour as
    /// `Package.swift`".
    ///
    /// Before the fix, `MappablePackageDependency.locationString`
    /// for `.workspaceInherited` returned `identity.description`
    /// (e.g. `"some-lib"`) instead of the resolved URL, so a
    /// URL-keyed mirror in `mirrors.json` was looked up against the
    /// identity and never matched. `swift package update` in a
    /// workspace then fetched the original unreachable URL from
    /// `Workspace.swift` rather than the mirror target — reproducing
    /// as `workspace_update_appliesWorkspaceRootMirror` in
    /// `WorkspaceFeatureTests`.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInherited_withRemoteSourceControlMirror_appliesMirrorSubstitution() throws {
        let originalURL = "https://example.invalid/some-lib"
        let mirrorURL = "https://mirror.example/some-lib"
        let identityResolver = DefaultIdentityResolver(
            locationMapper: { location in
                location == originalURL ? mirrorURL : location
            },
        )
        let mapper = DefaultDependencyMapper(identityResolver: identityResolver)

        let inherited = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .everything,
            traits: nil,
            resolved: .sourceControl(
                location: .remote(SourceControlURL(originalURL)),
                requirement: .range("1.0.0"..<"2.0.0"),
                nameForTargetDependencyResolutionOnly: nil,
                registryIdentity: nil,
            ),
        )
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .workspaceInherited(inherited),
            productFilter: .everything,
            traits: nil,
        )

        let mapped = try mapper.mappedDependency(dependency, fileSystem: InMemoryFileSystem())

        guard case .workspaceInherited(let mappedInherited) = mapped else {
            Issue.record("expected `.workspaceInherited` case preserved after mapping, got \(mapped)")
            return
        }
        guard case .sourceControl(let mappedLocation, _, _, _) = mappedInherited.resolved else {
            Issue.record("expected `.sourceControl` resolved kind, got \(String(describing: mappedInherited.resolved))")
            return
        }
        guard case .remote(let mappedURL) = mappedLocation else {
            Issue.record("expected `.remote` location, got \(mappedLocation)")
            return
        }
        #expect(
            mappedURL.absoluteString == mirrorURL,
            "expected mirror URL `\(mirrorURL)`, got `\(mappedURL.absoluteString)`",
        )
    }

    /// Regression guard for the mirror fix: a `.workspaceInherited`
    /// dep with a remote source-control resolved location and NO
    /// mirror configured must pass through untouched — same URL,
    /// same requirement, `.workspaceInherited` case preserved. The
    /// fix should route the URL through `mappedLocation(for:)` but
    /// only substitute when a mirror actually matches; otherwise the
    /// no-mirror single-package baseline breaks.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInherited_withNoMirror_passesThroughRemoteSourceControlUnchanged() throws {
        let url = "https://example.com/some-lib"
        // Identity resolver with the default identity locationMapper
        // (identity function) — models "no mirror set".
        let identityResolver = DefaultIdentityResolver()
        let mapper = DefaultDependencyMapper(identityResolver: identityResolver)

        let inherited = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .everything,
            traits: nil,
            resolved: .sourceControl(
                location: .remote(SourceControlURL(url)),
                requirement: .range("1.0.0"..<"2.0.0"),
                nameForTargetDependencyResolutionOnly: nil,
                registryIdentity: nil,
            ),
        )
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .workspaceInherited(inherited),
            productFilter: .everything,
            traits: nil,
        )

        let mapped = try mapper.mappedDependency(dependency, fileSystem: InMemoryFileSystem())

        guard case .workspaceInherited(let mappedInherited) = mapped else {
            Issue.record("expected `.workspaceInherited` case preserved, got \(mapped)")
            return
        }
        guard case .sourceControl(let mappedLocation, _, _, _) = mappedInherited.resolved else {
            Issue.record("expected `.sourceControl` resolved kind, got \(String(describing: mappedInherited.resolved))")
            return
        }
        guard case .remote(let mappedURL) = mappedLocation else {
            Issue.record("expected `.remote` location, got \(mappedLocation)")
            return
        }
        #expect(
            mappedURL.absoluteString == url,
            "expected URL to pass through unchanged; got `\(mappedURL.absoluteString)`",
        )
    }

    /// A `.workspaceInherited` dep with a local source-control
    /// resolved path — declared as `.package(path: "external/lib")`
    /// at the workspace level — must have that path substituted when
    /// a mirror targets it. Same "same behaviour as Package.swift"
    /// invariant: a mirror on a local path in a plain `Package.swift`
    /// rewrites the URL; the workspace-inherited case must do the
    /// same for members that inherit it.
    ///
    /// Before the fix, `.workspaceInherited.locationString` returned
    /// the identity, so a path-keyed mirror never matched and the
    /// dep passed through with the original local path.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInherited_withLocalSourceControlMirror_appliesMirrorSubstitution() throws {
        let originalPath = "/repo/external/some-lib"
        let mirrorURL = "https://mirror.example/some-lib"
        let identityResolver = DefaultIdentityResolver(
            locationMapper: { location in
                location == originalPath ? mirrorURL : location
            },
        )
        let mapper = DefaultDependencyMapper(identityResolver: identityResolver)

        let inherited = PackageDependency.WorkspaceInherited(
            identity: .plain("some-lib"),
            productFilter: .everything,
            traits: nil,
            resolved: .sourceControl(
                location: .local(try Basics.AbsolutePath(validating: originalPath)),
                requirement: .range("1.0.0"..<"2.0.0"),
                nameForTargetDependencyResolutionOnly: nil,
                registryIdentity: nil,
            ),
        )
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .workspaceInherited(inherited),
            productFilter: .everything,
            traits: nil,
        )

        let mapped = try mapper.mappedDependency(dependency, fileSystem: InMemoryFileSystem())

        guard case .workspaceInherited(let mappedInherited) = mapped else {
            Issue.record("expected `.workspaceInherited` case preserved after mapping, got \(mapped)")
            return
        }
        guard case .sourceControl(let mappedLocation, _, _, _) = mappedInherited.resolved else {
            Issue.record("expected `.sourceControl` resolved kind, got \(String(describing: mappedInherited.resolved))")
            return
        }
        guard case .remote(let mappedURL) = mappedLocation else {
            Issue.record("expected `.remote` location after mirror substitution, got \(mappedLocation)")
            return
        }
        #expect(
            mappedURL.absoluteString == mirrorURL,
            "expected mirror URL `\(mirrorURL)`, got `\(mappedURL.absoluteString)`",
        )
    }

    /// A `.workspaceInherited` dep with a `.registry` resolved kind
    /// and an identity mirror must have the identity substituted
    /// while keeping the outer `.workspaceInherited` case — same
    /// invariant as remote-source-control: mirrors rewrite the
    /// resolved location, not the workspace-inheritance semantic.
    ///
    /// Before the fix, an identity mirror on a `.workspaceInherited`
    /// dep collapsed the case to plain `.registry` because
    /// `DefaultDependencyMapper` fell through to the "mapping
    /// happened" branch that constructs a fresh `.registry` factory.
    /// Members inheriting through the workspace lost the
    /// workspace-inherited signal downstream.
    @Test(
        .tags(
            .FunctionalArea.WorkspaceManiest,
        ),
    )
    func workspaceInherited_withRegistryIdentityMirror_appliesMirrorSubstitution() throws {
        let originalIdentity = "some-lib"
        let mirroredIdentity = "corp.some-lib"
        let identityResolver = DefaultIdentityResolver(
            locationMapper: { location in
                location == originalIdentity ? mirroredIdentity : location
            },
        )
        let mapper = DefaultDependencyMapper(identityResolver: identityResolver)

        let inherited = PackageDependency.WorkspaceInherited(
            identity: .plain(originalIdentity),
            productFilter: .everything,
            traits: nil,
            resolved: .registry(requirement: .range("1.0.0"..<"2.0.0")),
        )
        let dependency = MappablePackageDependency(
            parentPackagePath: parentPath,
            kind: .workspaceInherited(inherited),
            productFilter: .everything,
            traits: nil,
        )

        let mapped = try mapper.mappedDependency(dependency, fileSystem: InMemoryFileSystem())

        guard case .workspaceInherited(let mappedInherited) = mapped else {
            Issue.record("expected `.workspaceInherited` case preserved after registry mirror, got \(mapped)")
            return
        }
        #expect(
            mappedInherited.identity == .plain(mirroredIdentity),
            "expected identity `\(mirroredIdentity)`, got `\(mappedInherited.identity)`",
        )
        guard case .registry = mappedInherited.resolved else {
            Issue.record("expected `.registry` resolved kind preserved, got \(String(describing: mappedInherited.resolved))")
            return
        }
    }
}

// MARK: - Test FileSystem stub

/// A minimal `FileSystem` whose only meaningful behavior is that
/// `homeDirectory` throws `FileSystemError(.unsupported)`. Mirrors the surface
/// area that production `GitFileSystemView` exposes for `~/` expansion. Every
/// other method traps so that any unexpected access during the test fails
/// loudly rather than silently returning bogus data.
private final class ThrowingHomeDirectoryFileSystem: FileSystem {
    var homeDirectory: TSCBasic.AbsolutePath {
        get throws { throw FileSystemError(.unsupported) }
    }

    var cachesDirectory: TSCBasic.AbsolutePath? { nil }

    var tempDirectory: TSCBasic.AbsolutePath {
        get throws { throw FileSystemError(.unsupported) }
    }

    var currentWorkingDirectory: TSCBasic.AbsolutePath? { nil }

    func exists(_ path: TSCBasic.AbsolutePath, followSymlink: Bool) -> Bool { unreachable() }
    func isDirectory(_ path: TSCBasic.AbsolutePath) -> Bool { unreachable() }
    func isFile(_ path: TSCBasic.AbsolutePath) -> Bool { unreachable() }
    func isExecutableFile(_ path: TSCBasic.AbsolutePath) -> Bool { unreachable() }
    func isSymlink(_ path: TSCBasic.AbsolutePath) -> Bool { unreachable() }
    func isReadable(_ path: TSCBasic.AbsolutePath) -> Bool { unreachable() }
    func isWritable(_ path: TSCBasic.AbsolutePath) -> Bool { unreachable() }
    func getDirectoryContents(_ path: TSCBasic.AbsolutePath) throws -> [String] { try unreachableThrowing() }
    func changeCurrentWorkingDirectory(to path: TSCBasic.AbsolutePath) throws { try unreachableThrowing() }
    func createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws { try unreachableThrowing() }
    func createSymbolicLink(_ path: TSCBasic.AbsolutePath, pointingAt destination: TSCBasic.AbsolutePath, relative: Bool) throws { try unreachableThrowing() }
    func readFileContents(_ path: TSCBasic.AbsolutePath) throws -> ByteString { try unreachableThrowing() }
    func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: ByteString) throws { try unreachableThrowing() }
    func removeFileTree(_ path: TSCBasic.AbsolutePath) throws { try unreachableThrowing() }
    func chmod(_ mode: FileMode, path: TSCBasic.AbsolutePath, options: Set<FileMode.Option>) throws { try unreachableThrowing() }
    func copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws { try unreachableThrowing() }
    func move(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws { try unreachableThrowing() }

    private func unreachable(function: StaticString = #function) -> Bool {
        Issue.record("ThrowingHomeDirectoryFileSystem.\(function) was called unexpectedly")
        return false
    }

    private func unreachableThrowing(function: StaticString = #function) throws -> Never {
        Issue.record("ThrowingHomeDirectoryFileSystem.\(function) was called unexpectedly")
        throw FileSystemError(.unsupported)
    }
}
