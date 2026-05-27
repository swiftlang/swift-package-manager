//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageModel
import XCTest

import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import enum TSCBasic.FileMode
import struct TSCBasic.FileSystemError

final class DependencyMapperTests: XCTestCase {
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
            XCTFail("expected fileSystem-kind dependency, got \(mapped)")
            throw FileSystemError(.unsupported)
        }
        return settings.path
    }

    func testTildePathIsExpandedAgainstHomeDirectory() throws {
        // InMemoryFileSystem provides a synthetic home at /home/user — the
        // happy path that should keep working after the regression fix.
        let resolved = try mappedFileSystemPath("~/Library/Stuff", fileSystem: InMemoryFileSystem())
        XCTAssertEqual(resolved.pathString, "/home/user/Library/Stuff")
    }

    func testTildePathThrowsInsteadOfCrashingWhenHomeDirectoryUnsupported() {
        // Regression test for rdar://177668882: a remote source-control
        // package whose manifest contains `.package(path: "~/...")` previously
        // crashed Xcode because the underlying GitFileSystemView's
        // `homeDirectory` aborted with `fatalError` instead of throwing. Make
        // sure the dependency mapper now produces an actionable error.
        XCTAssertThrowsError(
            try mappedFileSystemPath(
                "~/Documents/games/BoardGameKitHost",
                fileSystem: ThrowingHomeDirectoryFileSystem()
            )
        ) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("~/"), "expected error to mention the offending '~/' prefix; got: \(description)")
            XCTAssertTrue(description.contains("BoardGameKitHost"), "expected error to mention the offending dependency path; got: \(description)")
        }
    }

    func testAbsolutePathIsLeftAlone() throws {
        let resolved = try mappedFileSystemPath("/absolute/path", fileSystem: InMemoryFileSystem())
        XCTAssertEqual(resolved.pathString, "/absolute/path")
    }

    func testRelativePathIsResolvedAgainstParent() throws {
        let resolved = try mappedFileSystemPath("Sibling", fileSystem: InMemoryFileSystem())
        XCTAssertEqual(resolved.pathString, "/parent/Sibling")
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
    func getDirectoryContents(_ path: TSCBasic.AbsolutePath) throws -> [String] { unreachable() }
    func changeCurrentWorkingDirectory(to path: TSCBasic.AbsolutePath) throws { unreachable() }
    func createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws { unreachable() }
    func createSymbolicLink(_ path: TSCBasic.AbsolutePath, pointingAt destination: TSCBasic.AbsolutePath, relative: Bool) throws { unreachable() }
    func readFileContents(_ path: TSCBasic.AbsolutePath) throws -> ByteString { unreachable() }
    func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: ByteString) throws { unreachable() }
    func removeFileTree(_ path: TSCBasic.AbsolutePath) throws { unreachable() }
    func chmod(_ mode: FileMode, path: TSCBasic.AbsolutePath, options: Set<FileMode.Option>) throws { unreachable() }
    func copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws { unreachable() }
    func move(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws { unreachable() }

    private func unreachable(function: StaticString = #function) -> Never {
        XCTFail("ThrowingHomeDirectoryFileSystem.\(function) was called unexpectedly")
        fatalError("ThrowingHomeDirectoryFileSystem.\(function) was called unexpectedly")
    }
}
