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

    // MARK: - Coverage: all ResolvedInherited variants

    /// Round-trip preserves a `.sourceControl` `ResolvedInherited` payload
    /// (location, requirement, name-for-target-dep-resolution, registryIdentity).
    /// Guards against a future field addition on the source-control variant
    /// silently dropping through the mapper.

    /// Round-trip preserves a `.registry` `ResolvedInherited` payload.

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
