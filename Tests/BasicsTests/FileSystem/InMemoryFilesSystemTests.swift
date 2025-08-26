/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import struct TSCBasic.ByteString
import struct TSCBasic.FileSystemError

import Testing
import _InternalTestSupport

#if os(Linux)
let isLinux = true
#else
let isLinux = false
#endif

struct InMemoryFileSystemTests {
    @Test(
        arguments: [
            (
                path: "/",
                recurvise: true,
                expectedFiles: [
                    (p: "/", shouldExist: true)
                ],
                expectError: false
            ),
            (
                path: "/tmp",
                recurvise: true,
                expectedFiles: [
                    (p: "/", shouldExist: true),
                    (p: "/tmp", shouldExist: true),
                ],
                expectError: false
            ),
            (
                path: "/tmp/ws",
                recurvise: true,
                expectedFiles: [
                    (p: "/", shouldExist: true),
                    (p: "/tmp", shouldExist: true),
                    (p: "/tmp/ws", shouldExist: true),
                ],
                expectError: false
            ),
            (
                path: "/tmp/ws",
                recurvise: false,
                expectedFiles: [
                    (p: "/", shouldExist: true),
                    (p: "/tmp", shouldExist: true),
                    (p: "/tmp/ws", shouldExist: true),
                ],
                expectError: true
            ),
        ]
    )
    func creatingDirectoryCreatesInternalFiles(
        path: String,
        recursive: Bool,
        expectedFiles: [(String, Bool)],
        expectError: Bool
    ) async throws {
        let fs = InMemoryFileSystem()
        let pathUnderTest = AbsolutePath(path)

        func errorMessage(_ pa: AbsolutePath, _ exists: Bool) -> String {
            return
                "Path '\(pa) \(exists ? "should exists, but doesn't" : "should not exist, but does.")"
        }

        try withKnownIssue {
            try fs.createDirectory(pathUnderTest, recursive: recursive)

            for (p, shouldExist) in expectedFiles {
                let expectedPath = AbsolutePath(p)
                #expect(
                    fs.exists(expectedPath) == shouldExist,
                    "\(errorMessage(expectedPath, shouldExist))")
            }
        } when: {
            expectError
        }
    }


    @Test(
        arguments: [
            "/",
            "/tmp",
            "/tmp/",
            "/something/ws",
            "/something/ws/",
            "/what/is/this",
            "/what/is/this/",
        ]
    )
    func callingCreateDirectoryOnAnExistingDirectoryIsSuccessful(path: String) async throws {
        let root = AbsolutePath(path)
        let fs = InMemoryFileSystem()

        #expect(throws: Never.self) {
            try fs.createDirectory(root, recursive: true)
        }

        #expect(throws: Never.self) {
            try fs.createDirectory(root.appending("more"), recursive: true)
        }
    }

    struct writeFileContentsTests {

        @Test
        func testWriteFileContentsSuccessful() async throws {
            // GIVEN we have a filesytstem
            let fs = InMemoryFileSystem()
            // and a path
            let pathUnderTest = AbsolutePath("/myFile.zip")
            let expectedContents = ByteString([0xAA, 0xBB, 0xCC])

            // WHEN we write contents to the file
            try fs.writeFileContents(pathUnderTest, bytes: expectedContents)

            // THEN we expect the file to exist
            #expect(
                fs.exists(pathUnderTest),
                "Path \(pathUnderTest.pathString) does not exists when it should")
        }

        @Test
        func testWritingAFileWithANonExistingParentDirectoryFails() async throws {
            // GIVEN we have a filesytstem
            let fs = InMemoryFileSystem()
            // and a path
            let pathUnderTest = AbsolutePath("/tmp/myFile.zip")
            let expectedContents = ByteString([0xAA, 0xBB, 0xCC])

            // WHEN we write contents to the file
            // THEn we expect an error to occus
            withKnownIssue {
                try fs.writeFileContents(pathUnderTest, bytes: expectedContents)
            }

            // AND we expect the file to not exist
            #expect(
                !fs.exists(pathUnderTest),
                "Path \(pathUnderTest.pathString) does exists when it should not")
        }

        @Test
        func errorOccursWhenWritingToRootDirectory() async throws {
            // GIVEN we have a filesytstem
            let fs = InMemoryFileSystem()
            // and a path
            let pathUnderTest = AbsolutePath("/")
            let expectedContents = ByteString([0xAA, 0xBB, 0xCC])

            // WHEN we write contents to the file
            // THEN we expect an error to occur
            withKnownIssue {
                try fs.writeFileContents(pathUnderTest, bytes: expectedContents)
            }

        }

        @Test
        func testErrorOccursIfParentIsNotADirectory() async throws {
            // GIVEN we have a filesytstem
            let fs = InMemoryFileSystem()
            // AND an existing file
            let aFile = AbsolutePath("/foo")
            try fs.writeFileContents(aFile, bytes: "")

            // AND a the path under test that has an existing file as a parent
            let pathUnderTest = aFile.appending("myFile")
            let expectedContents = ByteString([0xAA, 0xBB, 0xCC])

            // WHEN we write contents to the file
            // THEN we expect an error to occur
            withKnownIssue {
                try fs.writeFileContents(pathUnderTest, bytes: expectedContents)
            }

        }
    }


    struct testReadFileContentsTests {
        @Test
        func readingAFileThatDoesNotExistsRaisesAnError() async throws {
            // GIVEN we have a filesystem
            let fs = InMemoryFileSystem()

            // WHEN we read a non-existing file
            // THEN an error occurs
            withKnownIssue {
                let _ = try fs.readFileContents("/file/does/not/exists")
            }
        }

        @Test
        func readingExistingFileReturnsExpectedContents() async throws {
            // GIVEN we have a filesytstem
            let fs = InMemoryFileSystem()
            // AND a file a path
            let pathUnderTest = AbsolutePath("/myFile.zip")
            let expectedContents = ByteString([0xAA, 0xBB, 0xCC])
            try fs.writeFileContents(pathUnderTest, bytes: expectedContents)

            // WHEN we read contents if the file
            let actualContents = try fs.readFileContents(pathUnderTest)

            // THEN the actual contents should match the expected to match the
            #expect(actualContents == expectedContents, "Actual is not as expected")
        }

        @Test
        func readingADirectoryFailsWithAnError() async throws {
            // GIVEN we have a filesytstem
            let fs = InMemoryFileSystem()
            // AND a file a path
            let pathUnderTest = AbsolutePath("/myFile.zip")
            let expectedContents = ByteString([0xAA, 0xBB, 0xCC])
            try fs.writeFileContents(pathUnderTest, bytes: expectedContents)

            // WHEN we read the contents of a directory
            // THEN we expect a failure to occur
            withKnownIssue {
                let _ = try fs.readFileContents(pathUnderTest.parentDirectory)
            }
        }
    }
}
