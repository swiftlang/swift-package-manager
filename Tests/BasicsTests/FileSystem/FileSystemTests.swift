//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCTestSupport
import Testing

@testable import Basics

struct FileSystemTests {
    // Regression test for https://github.com/swiftlang/swift-package-manager/issues/9915: localFileSystem.readFileContents must accept non-regular
    // files (FIFOs, /dev/stdin) after TSC switched from fopen/fread to Data(contentsOf:), which
    // rejects non-regular files on Linux (swift-foundation) and some macOS/Foundation versions.
    #if !os(Windows)
    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9915", relationship: .verifies),
    )
    func localFileSystemReadFileContentsAcceptsNonRegularFile() async throws {
        try await withTemporaryDirectory { tmpDir in
            let fifoPath = tmpDir.appending("token.fifo")

            let rc = mkfifo(fifoPath.pathString, 0o600)
            guard rc == 0 else {
                Issue.record("mkfifo failed: \(String(cString: strerror(errno)))")
                return
            }

            let expected = "test-secret-token"
            // FIFOs block open(2) until both ends are open, so write from a concurrent task.
            let writeTask = Task.detached {
                let fd = open(fifoPath.pathString, O_WRONLY)
                guard fd >= 0 else { return }
                defer { close(fd) }
                _ = expected.withCString { ptr in write(fd, ptr, strlen(ptr)) }
            }
            defer { writeTask.cancel() }

            let contents: String = try localFileSystem.readFileContents(fifoPath)
            #expect(contents == expected)
        }
    }
    #endif

    @Test
    func stripFirstLevelComponent() throws {
        let fileSystem = InMemoryFileSystem()

        let rootPath = AbsolutePath("/root")
        try fileSystem.createDirectory(rootPath)

        let totalDirectories = Int.random(in: 0..<100)
        for index in 0..<totalDirectories {
            let path = rootPath.appending("dir\(index)")
            try fileSystem.createDirectory(path, recursive: false)
        }

        let totalFiles = Int.random(in: 0..<100)
        for index in 0..<totalFiles {
            let path = rootPath.appending("file\(index)")
            try fileSystem.writeFileContents(path, string: "\(index)")
        }

        do {
            let contents = try fileSystem.getDirectoryContents(.root)
            #expect(contents.count == 1)
        }

        try fileSystem.stripFirstLevel(of: .root)

        do {
            let contents = Set(try fileSystem.getDirectoryContents(.root))
            #expect(contents.count == totalDirectories + totalFiles)

            for index in 0..<totalDirectories {
                #expect(contents.contains("dir\(index)"))
            }
            for index in 0..<totalFiles {
                #expect(contents.contains("file\(index)"))
            }
        }
    }

    @Test
    func stripFirstLevelComponentErrors() throws {
        let functionUnderTest = "stripFirstLevel"
        do {
            let fileSystem = InMemoryFileSystem()
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory"))
            {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }

        do {
            let fileSystem = InMemoryFileSystem()
            for index in 0..<3 {
                let path = AbsolutePath.root.appending("dir\(index)")
                try fileSystem.createDirectory(path, recursive: false)
            }
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory"))
            {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }

        do {
            let fileSystem = InMemoryFileSystem()
            for index in 0..<3 {
                let path = AbsolutePath.root.appending("file\(index)")
                try fileSystem.writeFileContents(path, string: "\(index)")
            }
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory"))
            {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }

        do {
            let fileSystem = InMemoryFileSystem()
            let path = AbsolutePath.root.appending("file")
            try fileSystem.writeFileContents(path, string: "")
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory"))
            {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }
    }

    @Test
    func validateNoEscapingSymlinksAllowsInternalSymlinks() throws {
        try withTemporaryDirectory { tmpDir in
            let dir = tmpDir.appending("extraction")
            try localFileSystem.createDirectory(dir, recursive: true)
            let subdir = dir.appending("sub")
            try localFileSystem.createDirectory(subdir)
            try localFileSystem.writeFileContents(subdir.appending("file.txt"), string: "content")
            try localFileSystem.createSymbolicLink(
                dir.appending("link"),
                pointingAt: subdir.appending("file.txt"),
                relative: true
            )

            #expect(throws: Never.self) {
                try localFileSystem.validateNoEscapingSymlinks(in: dir)
            }
        }
    }

    @Test
    func validateNoEscapingSymlinksRejectsEscapingAbsoluteSymlink() throws {
        try withTemporaryDirectory { tmpDir in
            let dir = tmpDir.appending("extraction")
            try localFileSystem.createDirectory(dir, recursive: true)
            try localFileSystem.createSymbolicLink(
                dir.appending("escape"),
                pointingAt: tmpDir,
                relative: false
            )

            #expect(throws: StringError.self) {
                try localFileSystem.validateNoEscapingSymlinks(in: dir)
            }
        }
    }

    @Test
    func validateNoEscapingSymlinksRejectsEscapingRelativeSymlink() throws {
        try withTemporaryDirectory { tmpDir in
            let dir = tmpDir.appending("extraction")
            try localFileSystem.createDirectory(dir, recursive: true)
            try localFileSystem.createSymbolicLink(
                dir.appending("escape"),
                pointingAt: tmpDir,
                relative: true
            )

            #expect(throws: StringError.self) {
                try localFileSystem.validateNoEscapingSymlinks(in: dir)
            }
        }
    }

    @Test
    func validateNoEscapingSymlinksRejectsNestedEscapingSymlink() throws {
        try withTemporaryDirectory { tmpDir in
            let dir = tmpDir.appending("extraction")
            let nested = dir.appending(components: "a", "b")
            try localFileSystem.createDirectory(nested, recursive: true)
            try localFileSystem.createSymbolicLink(
                nested.appending("escape"),
                pointingAt: tmpDir,
                relative: true
            )

            #expect(throws: StringError.self) {
                try localFileSystem.validateNoEscapingSymlinks(in: dir)
            }
        }
    }

    @Test
    func validateNoEscapingSymlinksEmptyDirectorySucceeds() throws {
        try withTemporaryDirectory { tmpDir in
            let dir = tmpDir.appending("extraction")
            try localFileSystem.createDirectory(dir, recursive: true)

            #expect(throws: Never.self) {
                try localFileSystem.validateNoEscapingSymlinks(in: dir)
            }
        }
    }

    @Test
    func checksumOfFileTracksContents() throws {
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/file")
        try fileSystem.writeFileContents(path, string: "contents")
        let original = try fileSystem.checksum(of: path)

        #expect(try fileSystem.checksum(of: path) == original)

        try fileSystem.writeFileContents(path, string: "different")
        #expect(try fileSystem.checksum(of: path) != original)
    }

    @Test
    func checksumOfDirectoryMatchesIdenticalTrees() throws {
        let fileSystem = InMemoryFileSystem()
        for root in ["/one", "/two"] {
            try fileSystem.writeFileContents(AbsolutePath("\(root)/a.txt"), string: "a")
            try fileSystem.writeFileContents(AbsolutePath("\(root)/nested/b.txt"), string: "b")
        }

        #expect(try fileSystem.checksum(of: "/one") == fileSystem.checksum(of: "/two"))
    }

    @Test
    func checksumOfDirectoryTracksNamesAndStructure() throws {
        let fileSystem = InMemoryFileSystem()
        let root = AbsolutePath("/bundle")
        try fileSystem.writeFileContents(root.appending("a.txt"), string: "a")
        let original = try fileSystem.checksum(of: root)

        try fileSystem.move(from: root.appending("a.txt"), to: root.appending("renamed.txt"))
        #expect(try fileSystem.checksum(of: root) != original)

        try fileSystem.move(from: root.appending("renamed.txt"), to: root.appending("a.txt"))
        #expect(try fileSystem.checksum(of: root) == original)

        try fileSystem.writeFileContents(root.appending("added.txt"), string: "")
        #expect(try fileSystem.checksum(of: root) != original)
    }

    @Test
    func checksumOfDirectoryTracksEmptySubdirectories() throws {
        let fileSystem = InMemoryFileSystem()
        let root = AbsolutePath("/bundle")
        try fileSystem.writeFileContents(root.appending("a.txt"), string: "a")
        let original = try fileSystem.checksum(of: root)

        try fileSystem.createDirectory(root.appending("empty"))
        #expect(try fileSystem.checksum(of: root) != original)
    }
}
