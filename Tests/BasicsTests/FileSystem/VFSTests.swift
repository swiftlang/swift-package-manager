//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import func TSCBasic.withTemporaryFile
import XCTest

import struct TSCBasic.ByteString

import _InternalTestSupport // for skipOnWindowsAsTestCurrentlyFails

func testWithTemporaryDirectory(
    function: StaticString = #function,
    body: @escaping (AbsolutePath) async throws -> Void
) async throws {
    let cleanedFunction = function.description
        .replacingOccurrences(of: "(", with: "")
        .replacingOccurrences(of: ")", with: "")
        .replacingOccurrences(of: ".", with: "")
    try await withTemporaryDirectory(prefix: "spm-tests-\(cleanedFunction)") { tmpDirPath in
        defer {
            // Unblock and remove the tmp dir on deinit.
            try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
            try? localFileSystem.removeFileTree(tmpDirPath)
        }
        try await  body(tmpDirPath)
    }.value
}

class VFSTests: XCTestCase {
    func testLocalBasics() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        // tiny PE binary from: https://archive.is/w01DO
        let contents: [UInt8] = [
          0x4d, 0x5a, 0x00, 0x00, 0x50, 0x45, 0x00, 0x00, 0x4c, 0x01, 0x01, 0x00,
          0x6a, 0x2a, 0x58, 0xc3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x04, 0x00, 0x03, 0x01, 0x0b, 0x01, 0x08, 0x00, 0x04, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00,
          0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
          0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x68, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x02
        ]

        let fs = localFileSystem
        try withTemporaryFile { [contents] vfsPath in
            try withTemporaryDirectory(removeTreeOnDeinit: true) { [contents] tempDirPath in
                let file = tempDirPath.appending("best")
                try fs.writeFileContents(file, string: "best")

                let sym = tempDirPath.appending("hello")
                try fs.createSymbolicLink(sym, pointingAt: file, relative: false)

                let executable = tempDirPath.appending("exec-foo")
                try fs.writeFileContents(executable, bytes: ByteString(contents))
#if !os(Windows)
                try fs.chmod(.executable, path: executable, options: [])
#endif

                let executableSym = tempDirPath.appending("exec-sym")
                try fs.createSymbolicLink(executableSym, pointingAt: executable, relative: false)

                try fs.createDirectory(tempDirPath.appending("dir"))
                try fs.writeFileContents(tempDirPath.appending(components: ["dir", "file"]), bytes: [])

                try VirtualFileSystem.serializeDirectoryTree(tempDirPath, into: AbsolutePath(vfsPath.path), fs: fs, includeContents: [executable])
            }

            let vfs = try VirtualFileSystem(path: vfsPath.path, fs: fs)

            // exists()
            XCTAssertTrue(vfs.exists(AbsolutePath("/")))
            XCTAssertFalse(vfs.exists(AbsolutePath("/does-not-exist")))

            // isFile()
            let filePath = AbsolutePath("/best")
            XCTAssertTrue(vfs.exists(filePath))
            XCTAssertTrue(vfs.isFile(filePath))
            XCTAssertEqual(try vfs.getFileInfo(filePath).fileType, .typeRegular)
            XCTAssertFalse(vfs.isDirectory(filePath))
            XCTAssertFalse(vfs.isFile(AbsolutePath("/does-not-exist")))
            XCTAssertFalse(vfs.isSymlink(AbsolutePath("/does-not-exist")))
            XCTAssertThrowsError(try vfs.getFileInfo(AbsolutePath("/does-not-exist")))

            // isSymlink()
            let symPath = AbsolutePath("/hello")
            XCTAssertTrue(vfs.isSymlink(symPath))
            XCTAssertTrue(vfs.isFile(symPath))
            XCTAssertEqual(try vfs.getFileInfo(symPath).fileType, .typeSymbolicLink)
            XCTAssertFalse(vfs.isDirectory(symPath))

            // isExecutableFile
            let executablePath = AbsolutePath("/exec-foo")
            let executableSymPath = AbsolutePath("/exec-sym")
            XCTAssertTrue(vfs.isExecutableFile(executablePath))
            XCTAssertTrue(vfs.isExecutableFile(executableSymPath))
            XCTAssertTrue(vfs.isSymlink(executableSymPath))
            XCTAssertFalse(vfs.isExecutableFile(symPath))
            XCTAssertFalse(vfs.isExecutableFile(filePath))
            XCTAssertFalse(vfs.isExecutableFile(AbsolutePath("/does-not-exist")))
            XCTAssertFalse(vfs.isExecutableFile(AbsolutePath("/")))

            // readFileContents
            let execFileContents = try vfs.readFileContents(executablePath)
            XCTAssertEqual(execFileContents, ByteString(contents))

            // isDirectory()
            XCTAssertTrue(vfs.isDirectory(AbsolutePath("/")))
            XCTAssertFalse(vfs.isDirectory(AbsolutePath("/does-not-exist")))

            // getDirectoryContents()
            do {
                _ = try vfs.getDirectoryContents(AbsolutePath("/does-not-exist"))
                XCTFail("Unexpected success")
            } catch {
                XCTAssertEqual(error.localizedDescription, "no such file or directory: \(AbsolutePath("/does-not-exist"))")
            }

            let thisDirectoryContents = try vfs.getDirectoryContents(AbsolutePath("/"))
            XCTAssertFalse(thisDirectoryContents.contains(where: { $0 == "." }))
            XCTAssertFalse(thisDirectoryContents.contains(where: { $0 == ".." }))
            XCTAssertEqual(thisDirectoryContents.sorted(), ["best", "dir", "exec-foo", "exec-sym", "hello"])

            let contents = try vfs.getDirectoryContents(AbsolutePath("/dir"))
            XCTAssertEqual(contents, ["file"])

            let fileContents = try vfs.readFileContents(AbsolutePath("/dir/file"))
            XCTAssertEqual(fileContents, "")
        }
    }
}
