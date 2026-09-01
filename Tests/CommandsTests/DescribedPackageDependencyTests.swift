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
import Testing
import _InternalTestSupport

import struct TSCUtility.Version

/// Coverage for `DescribedPackageDependency.init(from:)`'s handling
/// of workspace-inherited dependencies. The workspaces pipeline
/// preserves `.workspaceInherited` end-to-end (only the outer
/// `resolved:` field is populated by `resolveInherited`), so
/// describe must handle the case natively rather than assuming a
/// rewrite pass replaces it with a concrete kind.
@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct DescribedPackageDependencyTests {
    /// A `.workspaceInherited` whose `resolved` is `.fileSystem`
    /// (workspace declared the dep via `.package(path:)`) round-trips
    /// into `DescribedPackageDependency.workspaceInherited` carrying
    /// the resolved path.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func init_fromWorkspaceInheritedFileSystem_producesWorkspaceInheritedCase() throws {
        let externalPath = AbsolutePath("/repo/external/traited-lib")
        let inherited = PackageDependency.workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: PackageIdentity.plain("traited-lib"),
                productFilter: .everything,
                traits: [
                    PackageDependency.Trait(name: "core"),
                ],
                resolved: .fileSystem(
                    path: externalPath,
                    nameForTargetDependencyResolutionOnly: nil,
                ),
            )
        )

        let described = DescribedPackage.DescribedPackageDependency(from: inherited)

        guard case .workspaceInherited(let identity, let resolved) = described else {
            Issue.record("expected .workspaceInherited case, got: \(described)")
            return
        }
        #expect(identity.description == "traited-lib")
        guard case .fileSystem(let path) = resolved else {
            Issue.record("expected .fileSystem resolved kind, got: \(resolved)")
            return
        }
        #expect(path == externalPath)
    }

    /// A `.workspaceInherited` whose `resolved` is `.sourceControl`
    /// (workspace declared the dep via `.package(url:)`) round-trips
    /// into the describe representation carrying the remote URL.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func init_fromWorkspaceInheritedSourceControlRemote_producesWorkspaceInheritedCase() throws {
        let url = SourceControlURL("https://github.com/apple/swift-nio")
        let requirement: PackageDependency.SourceControl.Requirement = .range(
            Version(2, 0, 0) ..< Version(3, 0, 0),
        )
        let inherited = PackageDependency.workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: PackageIdentity.plain("swift-nio"),
                productFilter: .everything,
                traits: nil,
                resolved: .sourceControl(
                    location: .remote(url),
                    requirement: requirement,
                    nameForTargetDependencyResolutionOnly: nil,
                    registryIdentity: nil,
                ),
            )
        )

        let described = DescribedPackage.DescribedPackageDependency(from: inherited)

        guard case .workspaceInherited(let identity, let resolved) = described else {
            Issue.record("expected .workspaceInherited case, got: \(described)")
            return
        }
        #expect(identity.description == "swift-nio")
        guard case .sourceControl(let location, let describedRequirement) = resolved else {
            Issue.record("expected .sourceControl resolved kind, got: \(resolved)")
            return
        }
        #expect(location == url.absoluteString)
        #expect(describedRequirement == requirement)
    }

    /// A `.workspaceInherited` whose `resolved` is `.registry`
    /// (workspace declared the dep via `.package(id:)`) round-trips
    /// into the describe representation carrying the requirement.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func init_fromWorkspaceInheritedRegistry_producesWorkspaceInheritedCase() throws {
        let requirement: PackageDependency.Registry.Requirement = .range(
            Version(1, 0, 0) ..< Version(2, 0, 0),
        )
        let inherited = PackageDependency.workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: PackageIdentity.plain("scope.log-lib"),
                productFilter: .everything,
                traits: nil,
                resolved: .registry(requirement: requirement),
            )
        )

        let described = DescribedPackage.DescribedPackageDependency(from: inherited)

        guard case .workspaceInherited(let identity, let resolved) = described else {
            Issue.record("expected .workspaceInherited case, got: \(described)")
            return
        }
        #expect(identity.description == "scope.log-lib")
        guard case .registry(let describedRequirement) = resolved else {
            Issue.record("expected .registry resolved kind, got: \(resolved)")
            return
        }
        #expect(describedRequirement == requirement)
    }

    /// A `.workspaceInherited` whose `resolved` is `.sourceControl`
    /// with a `.local` location (rare — workspace declared a
    /// URL-shaped dep pointing at a local path) round-trips as
    /// source-control with a path-form location.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func init_fromWorkspaceInheritedSourceControlLocal_producesWorkspaceInheritedCase() throws {
        let localPath = AbsolutePath("/repo/checkouts/some-lib")
        let requirement: PackageDependency.SourceControl.Requirement = .branch("main")
        let inherited = PackageDependency.workspaceInherited(
            PackageDependency.WorkspaceInherited(
                identity: PackageIdentity.plain("some-lib"),
                productFilter: .everything,
                traits: nil,
                resolved: .sourceControl(
                    location: .local(localPath),
                    requirement: requirement,
                    nameForTargetDependencyResolutionOnly: nil,
                    registryIdentity: nil,
                ),
            )
        )

        let described = DescribedPackage.DescribedPackageDependency(from: inherited)

        guard case .workspaceInherited(_, let resolved) = described else {
            Issue.record("expected .workspaceInherited case, got: \(described)")
            return
        }
        guard case .sourceControl(let location, _) = resolved else {
            Issue.record("expected .sourceControl resolved kind, got: \(resolved)")
            return
        }
        #expect(location == localPath.pathString)
    }
}
