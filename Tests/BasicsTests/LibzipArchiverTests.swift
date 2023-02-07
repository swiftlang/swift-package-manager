//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import TSCBasic
import TSCTestSupport
import XCTest

class LibzipArchiverTests: XCTestCase {
    func testZipArchiverSuccess() throws {
        try testWithTemporaryDirectory { tmpdir in
            let archiver = LibzipArchiver(fileSystem: localFileSystem)
            let inputArchivePath = AbsolutePath(path: #file).parentDirectory
                .appending(components: "Inputs", "archive.zip")
            try archiver.extract(from: inputArchivePath, to: tmpdir)
            let content = tmpdir.appending(component: "file")
            XCTAssert(localFileSystem.exists(content))
            XCTAssertEqual((try? localFileSystem.readFileContents(content))?.cString, "Hello World!")
        }
    }

    func testZipArchiverArchiveDoesntExist() {
        let fileSystem = InMemoryFileSystem()
        let archiver = LibzipArchiver(fileSystem: fileSystem)
        let archive = AbsolutePath(path: "/archive.zip")
        XCTAssertThrowsError(try archiver.extract(from: archive, to: AbsolutePath(path: "/"))) { error in
            XCTAssertEqual(error as? FileSystemError, FileSystemError(.noEntry, archive))
        }
    }

    func testZipArchiverDestinationDoesntExist() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: "/archive.zip")
        let archiver = LibzipArchiver(fileSystem: fileSystem)
        let destination = AbsolutePath(path: "/destination")
        XCTAssertThrowsError(try archiver.extract(from: AbsolutePath(path: "/archive.zip"), to: destination)) { error in
            XCTAssertEqual(error as? FileSystemError, FileSystemError(.notDirectory, destination))
        }
    }

    func testZipArchiverDestinationIsFile() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: "/archive.zip", "/destination")
        let archiver = LibzipArchiver(fileSystem: fileSystem)
        let destination = AbsolutePath(path: "/destination")
        XCTAssertThrowsError(try archiver.extract(from: AbsolutePath(path: "/archive.zip"), to: destination)) { error in
            XCTAssertEqual(error as? FileSystemError, FileSystemError(.notDirectory, destination))
        }
    }

    func testZipArchiverInvalidArchive() throws {
        try testWithTemporaryDirectory { tmpdir in
            let archiver = LibzipArchiver(fileSystem: localFileSystem)
            let inputArchivePath = AbsolutePath(path: #file).parentDirectory
                .appending(components: "Inputs", "invalid_archive.zip")
            XCTAssertThrowsError(try archiver.extract(from: inputArchivePath, to: tmpdir)) { error in
                XCTAssertMatch("\(error)", .contains("Not a zip archive"))
            }
        }
    }

    func testValidation() throws {
        // valid
        try testWithTemporaryDirectory { _ in
            let archiver = LibzipArchiver(fileSystem: localFileSystem)
            let path = AbsolutePath(path: #file).parentDirectory
                .appending(components: "Inputs", "archive.zip")
            XCTAssertTrue(try archiver.validate(path: path))
        }
        // invalid
        try testWithTemporaryDirectory { _ in
            let archiver = LibzipArchiver(fileSystem: localFileSystem)
            let path = AbsolutePath(path: #file).parentDirectory
                .appending(components: "Inputs", "invalid_archive.zip")
            XCTAssertFalse(try archiver.validate(path: path))
        }
        // error
        try testWithTemporaryDirectory { _ in
            let archiver = LibzipArchiver(fileSystem: localFileSystem)
            let path = AbsolutePath.root.appending(component: "does_not_exist.zip")
            XCTAssertThrowsError(try archiver.validate(path: path)) { error in
                XCTAssertEqual(error as? FileSystemError, FileSystemError(.noEntry, path))
            }
        }
    }

    func testCompress() throws {
        try testWithTemporaryDirectory { tmpdir in
            let archiver = LibzipArchiver(fileSystem: localFileSystem)

            let rootDir = tmpdir.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(rootDir)
            try localFileSystem.writeFileContents(rootDir.appending(component: "file1.txt"), string: "Hello World!")

            let dir1 = rootDir.appending(component: "dir1")
            try localFileSystem.createDirectory(dir1)
            try localFileSystem.writeFileContents(dir1.appending(component: "file2.txt"), string: "Hello World 2!")

            let dir2 = dir1.appending(component: "dir2")
            try localFileSystem.createDirectory(dir2)
            try localFileSystem.writeFileContents(dir2.appending(component: "file3.txt"), string: "Hello World 3!")
            try localFileSystem.writeFileContents(dir2.appending(component: "file4.txt"), string: "Hello World 4!")

            let archivePath = tmpdir.appending(component: UUID().uuidString + ".zip")
            try archiver.compress(directory: rootDir, to: archivePath)
            XCTAssertFileExists(archivePath)

            let extractRootDir = tmpdir.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(extractRootDir)
            try archiver.extract(from: archivePath, to: extractRootDir)
            try localFileSystem.stripFirstLevel(of: extractRootDir)

            XCTAssertFileExists(extractRootDir.appending(component: "file1.txt"))
            XCTAssertEqual(
                try? localFileSystem.readFileContents(extractRootDir.appending(component: "file1.txt")),
                "Hello World!"
            )

            let extractedDir1 = extractRootDir.appending(component: "dir1")
            XCTAssertDirectoryExists(extractedDir1)
            XCTAssertFileExists(extractedDir1.appending(component: "file2.txt"))
            XCTAssertEqual(
                try? localFileSystem.readFileContents(extractedDir1.appending(component: "file2.txt")),
                "Hello World 2!"
            )

            let extractedDir2 = extractedDir1.appending(component: "dir2")
            XCTAssertDirectoryExists(extractedDir2)
            XCTAssertFileExists(extractedDir2.appending(component: "file3.txt"))
            XCTAssertEqual(
                try? localFileSystem.readFileContents(extractedDir2.appending(component: "file3.txt")),
                "Hello World 3!"
            )
            XCTAssertFileExists(extractedDir2.appending(component: "file4.txt"))
            XCTAssertEqual(
                try? localFileSystem.readFileContents(extractedDir2.appending(component: "file4.txt")),
                "Hello World 4!"
            )
        }
    }
}
