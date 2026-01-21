//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics
import struct TSCBasic.ByteString
import struct TSCBasic.FileSystemError

import Testing
import _InternalTestSupport

@Suite(
    .tags(
        .TestSize.small,
        .Platform.FileSystem,
    ),
)
struct InMemoryFileSystemTests {
    private static let testFileContent = ByteString([0xAA, 0xBB, 0xCC])

    @Test(
        arguments: [
            (
                path: "/",
                recursive: true,
                expectedFiles: [
                    (p: "/", shouldExist: true)
                ],
                expectError: false
            ),
            (
                path: "/tmp",
                recursive: true,
                expectedFiles: [
                    (p: "/", shouldExist: true),
                    (p: "/tmp", shouldExist: true),
                ],
                expectError: false
            ),
            (
                path: "/tmp/ws",
                recursive: true,
                expectedFiles: [
                    (p: "/", shouldExist: true),
                    (p: "/tmp", shouldExist: true),
                    (p: "/tmp/ws", shouldExist: true),
                ],
                expectError: false
            ),
            (
                path: "/tmp/ws",
                recursive: false,
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
        if expectError {
            #expect(throws: FileSystemError.self) {
                try fs.createDirectory(pathUnderTest, recursive: recursive)
            }
        } else {
            #expect(throws: Never.self) {
                try fs.createDirectory(pathUnderTest, recursive: recursive)

                for (p, shouldExist) in expectedFiles {
                    let expectedPath = AbsolutePath(p)
                    #expect(
                        fs.exists(expectedPath) == shouldExist,
                        "\(errorMessage(expectedPath, shouldExist))")
                }
            }
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
            let fs = InMemoryFileSystem()
            let pathUnderTest = AbsolutePath("/myFile.zip")

            try fs.writeFileContents(pathUnderTest, bytes: testFileContent)

            #expect(
                fs.exists(pathUnderTest),
                "Path \(pathUnderTest.pathString) does not exists when it should")
        }

        @Test
        func testWritingAFileWithANonExistingParentDirectoryFails() async throws {
            let fs = InMemoryFileSystem()
            let pathUnderTest = AbsolutePath("/tmp/myFile.zip")

            #expect(throws: FileSystemError.self) {
                try fs.writeFileContents(pathUnderTest, bytes: testFileContent)
            }

            #expect(
                !fs.exists(pathUnderTest),
                "Path \(pathUnderTest.pathString) does exists when it should not")
        }

        @Test
        func errorOccursWhenWritingToRootDirectory() async throws {
            let fs = InMemoryFileSystem()
            let pathUnderTest = AbsolutePath("/")

            #expect(throws: FileSystemError.self) {
                try fs.writeFileContents(pathUnderTest, bytes: testFileContent)
            }
        }

        @Test
        func testErrorOccursIfParentIsNotADirectory() async throws {
            let fs = InMemoryFileSystem()
            let aFile = AbsolutePath("/foo")
            try fs.writeFileContents(aFile, bytes: "")

            let pathUnderTest = aFile.appending("myFile")

            #expect(throws: FileSystemError.self) {
                try fs.writeFileContents(pathUnderTest, bytes: testFileContent)
            }

        }
    }

    struct testReadFileContentsTests {
        @Test
        func readingAFileThatDoesNotExistsRaisesAnError() async throws {
            let fs = InMemoryFileSystem()
            #expect(throws: FileSystemError.self) {
                try fs.readFileContents("/file/does/not/exists")
            }
        }

        @Test
        func readingExistingFileReturnsExpectedContents() async throws {
            let fs = InMemoryFileSystem()
            let pathUnderTest = AbsolutePath("/myFile.zip")
            try fs.writeFileContents(pathUnderTest, bytes: testFileContent)

            let actualContents = try fs.readFileContents(pathUnderTest)

            #expect(actualContents == testFileContent, "Actual is not as expected")
        }

        @Suite(
            .tags(
                .TestSize.small,
            ),
        )
        struct ChangeCurrentWorkingDirectoryTests {
            func errorOccursWhenChangingDirectoryToAFile() async throws {
                let fileUnderTest = AbsolutePath.root.appending(components: "Foo", "Bar", "baz.txt")

                let fs = InMemoryFileSystem(
                    emptyFiles: [
                        fileUnderTest.pathString
                    ]
                )

                #expect(throws: FileSystemError(.notDirectory, fileUnderTest)) {
                    try fs.changeCurrentWorkingDirectory(to: fileUnderTest)
                }
            }

            func errorOccursWhenChangingDirectoryDoesNotExists() async throws {
                let fs = InMemoryFileSystem()
                let nonExistingDirectory = AbsolutePath.root.appending(components: "does-not-exists")

                #expect(throws: FileSystemError(.noEntry, nonExistingDirectory)) {
                    try fs.changeCurrentWorkingDirectory(to: nonExistingDirectory)
                }
            }

            func changinDirectoryToTheParentOfAnExistingFileIsSuccessful() async throws {
                let fileUnderTest = AbsolutePath.root.appending(components: "Foo", "Bar", "baz.txt")

                let fs = InMemoryFileSystem(
                    emptyFiles: [
                        fileUnderTest.pathString
                    ]
                )

                #expect(throws: Never.self) {
                    try fs.changeCurrentWorkingDirectory(to: fileUnderTest.parentDirectory)
                }
            }
        }

        @Suite(
            .tags(
                .TestSize.small,
            ),
        )
        struct GetDirectoryContentsTests {
            func returnsExpectedItemsWhenDirectoryHasASingleFile() async throws {
                let fileUnderTest = AbsolutePath.root.appending(components: "Foo", "Bar", "baz.txt")
                let fs = InMemoryFileSystem(
                    emptyFiles: [
                        fileUnderTest.pathString
                    ]
                )

                try fs.changeCurrentWorkingDirectory(to: fileUnderTest.parentDirectory)
                let contents = try fs.getDirectoryContents(fileUnderTest.parentDirectory)

                #expect(["baz.txt"] == contents)
            }
        }

        @Test
        func readingADirectoryFailsWithAnError() async throws {
            let fs = InMemoryFileSystem()
            let pathUnderTest = AbsolutePath("/myFile.zip")
            try fs.writeFileContents(pathUnderTest, bytes: testFileContent)

            #expect(throws: FileSystemError.self) {
                try fs.readFileContents(pathUnderTest.parentDirectory)
            }
        }
    }
}
