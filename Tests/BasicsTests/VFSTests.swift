/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import TSCBasic
import XCTest

class VFSTests: XCTestCase {
    func testLocalBasics() throws {
        let fs = TSCBasic.localFileSystem
        try withTemporaryFile { vfsPath in
            try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
                let file = tempDirPath.appending(component: "best")
                try fs.writeFileContents(file, string: "best")

                let sym = tempDirPath.appending(component: "hello")
                try fs.createSymbolicLink(sym, pointingAt: file, relative: false)

                let executable = tempDirPath.appending(component: "exec-foo")
                let executableSym = tempDirPath.appending(component: "exec-sym")
                try fs.createSymbolicLink(executableSym, pointingAt: executable, relative: false)
                let stream = BufferedOutputByteStream()
                stream <<< """
                    #!/bin/sh
                    set -e
                    exit

                    """
                try fs.writeFileContents(executable, bytes: stream.bytes)
                try Process.checkNonZeroExit(args: "chmod", "+x", executable.pathString)

                try fs.createDirectory(tempDirPath.appending(component: "dir"))
                try fs.writeFileContents(tempDirPath.appending(components: ["dir", "file"]), body: { _ in })

                try VirtualFileSystem.serializeDirectoryTree(tempDirPath, into: vfsPath.path, fs: fs, includeContents: [executable])
            }

            let vfs = try VirtualFileSystem(path: vfsPath.path, fs: fs)

            // exists()
            XCTAssert(vfs.exists(AbsolutePath("/")))
            XCTAssert(!vfs.exists(AbsolutePath("/does-not-exist")))

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
            XCTAssertEqual(execFileContents, "#!/bin/sh\nset -e\nexit\n")

            // isDirectory()
            XCTAssert(vfs.isDirectory(AbsolutePath("/")))
            XCTAssert(!vfs.isDirectory(AbsolutePath("/does-not-exist")))

            // getDirectoryContents()
            do {
                _ = try vfs.getDirectoryContents(AbsolutePath("/does-not-exist"))
                XCTFail("Unexpected success")
            } catch {
                XCTAssertEqual(error.localizedDescription, "no such file or directory: /does-not-exist")
            }

            let thisDirectoryContents = try vfs.getDirectoryContents(AbsolutePath("/"))
            XCTAssertTrue(!thisDirectoryContents.contains(where: { $0 == "." }))
            XCTAssertTrue(!thisDirectoryContents.contains(where: { $0 == ".." }))
            XCTAssertEqual(thisDirectoryContents.sorted(), ["best", "dir", "exec-foo", "exec-sym", "hello"])

            let contents = try vfs.getDirectoryContents(AbsolutePath("/dir"))
            XCTAssertEqual(contents, ["file"])

            let fileContents = try vfs.readFileContents(AbsolutePath("/dir/file"))
            XCTAssertEqual(fileContents, "")
        }
    }
}
