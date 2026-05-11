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

// import class Basics.InMemoryFileSystem
import struct Basics.AbsolutePath
import protocol Basics.FileSystem
import class Basics.ObservabilitySystem
import func Basics.resolveSymlinks
import func Basics.withTemporaryDirectory
import var Basics.localFileSystem
import struct TSCBasic.StringError
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import enum TSCBasic.FileMode

import func SwiftBuildSupport.createBuildSymbolicLinks

import _InternalTestSupport
import Testing

typealias AbsolutePath = Basics.AbsolutePath

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct CreateBuildSymbolicLinkFunction {
    @Test()
    func createBuildSymbolicLinkCreation() async throws {
        let fs = localFileSystem
        try withTemporaryDirectory(removeTreeOnDeinit: false) { tmpDir in
            // Arrange
            let observability = ObservabilitySystem.makeForTesting()
            let source = tmpDir.appending("source")
            let target = tmpDir.appending(components: "my", "target", "directory")
            try localFileSystem.createDirectory(target, recursive: true)

            // Act
            createBuildSymbolicLinks(
                source,
                pointingAt: target,
                fileSystem: fs,
                observabilityScope: observability.topScope,
            )

            // Assert
            try expectSymlink(
                source,
                pointsTo: target,
                fileSystem: fs,
            )
            expectNoDiagnostics(observability.diagnostics)
        }
    }

    @Test
    func failingToRemoveSourceSymlinkGeneratedAWarning() async throws {
        // Arrange
        struct FileSystemDouble: FileSystem {
            func createSymbolicLink(_ path: TSCBasic.AbsolutePath, pointingAt destination: TSCBasic.AbsolutePath, relative: Bool) throws {
                throw StringError("Purposely failing in \(#function)")
            }

            func removeFileTree(_ path: TSCBasic.AbsolutePath) throws {
                throw StringError("Purposely failing in \(#function)")
            }

            func removeFileTree(_ path: AbsolutePath) throws {
                throw StringError("Purposely failing in \(#function)")
            }
            func createSymbolicLink(source: AbsolutePath, pointingAt target: AbsolutePath) throws {
                throw StringError("Purposely failing in \(#function)")
            }

            func move(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {}
            func copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {}
            func chmod(_ mode: TSCBasic.FileMode, path: TSCBasic.AbsolutePath, options: Set<TSCBasic.FileMode.Option>) throws {}
            func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: TSCBasic.ByteString) throws {}
            func readFileContents(_ path: TSCBasic.AbsolutePath) throws -> TSCBasic.ByteString {
                TSCBasic.ByteString()
            }
            func createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws {}
            let tempDirectory: TSCBasic.AbsolutePath
            let cachesDirectory: TSCBasic.AbsolutePath?
            let homeDirectory: TSCBasic.AbsolutePath
            func changeCurrentWorkingDirectory(to path: TSCBasic.AbsolutePath) throws {}
            let currentWorkingDirectory: TSCBasic.AbsolutePath?
            func getDirectoryContents(_ path: TSCBasic.AbsolutePath) throws -> [String] {
                return []
            }
            func isWritable(_ path: TSCBasic.AbsolutePath) -> Bool { false }
            func isReadable(_ path: TSCBasic.AbsolutePath) -> Bool { false }
            func isSymlink(_ path: TSCBasic.AbsolutePath) -> Bool { false }
            func isExecutableFile(_ path: TSCBasic.AbsolutePath) -> Bool { false }
            func isFile(_ path: TSCBasic.AbsolutePath) -> Bool { false }
            func isDirectory(_ path: TSCBasic.AbsolutePath) -> Bool { false }
            func exists(_ path: TSCBasic.AbsolutePath, followSymlink: Bool) -> Bool { false }
            func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool { false }
        }

        let fs = FileSystemDouble(
            tempDirectory: TSCBasic.AbsolutePath.root.appending(components: "tmp", "\(#function)", "tmp"),
            cachesDirectory: nil,
            homeDirectory: TSCBasic.AbsolutePath.root.appending(components: "tmp", "\(#function)", "home"),
            currentWorkingDirectory: nil,
        )
        let observability = ObservabilitySystem.makeForTesting()

        // Act
        createBuildSymbolicLinks(
            AbsolutePath("/foo/bar"),
            pointingAt: AbsolutePath("/foo/ping/pong"),
            fileSystem: fs,
            observabilityScope: observability.topScope,
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: .contains("unable to delete"),
                severity: .warning
            )

            result.check(
                diagnostic: .contains("unable to create symbolic link"),
                severity: .warning
            )

        }
    }

}
