/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import POSIX
import Utility

func XCTAssertThrows<T where T: Swift.Error, T: Equatable>(_ expectedError: T, file: StaticString = #file, line: UInt = #line, _ body: () throws -> ()) {
    do {
        try body()
        XCTFail("body completed successfully", file: file, line: line)
    } catch let error as T {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("unexpected error thrown", file: file, line: line)
    }
}

class FileSystemTests: XCTestCase {

    // MARK: LocalFS Tests

    func testLocalBasics() {
        let fs = Basic.localFileSystem

        // exists()
        XCTAssert(fs.exists(AbsolutePath("/")))
        XCTAssert(!fs.exists(AbsolutePath("/does-not-exist")))

        // isFile()
        let file = try! TemporaryFile()
        XCTAssertTrue(fs.exists(file.path))
        XCTAssertTrue(fs.isFile(file.path))
        XCTAssertFalse(fs.isDirectory(file.path))
        XCTAssertFalse(fs.isFile(AbsolutePath("/does-not-exist")))
        XCTAssertFalse(fs.isSymlink(AbsolutePath("/does-not-exist")))

        // isSymlink()
        let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        let sym = tempDir.path.appending(component: "hello")
        try! createSymlink(sym, pointingAt: file.path)
        XCTAssertTrue(fs.isSymlink(sym))
        XCTAssertTrue(fs.isFile(sym))
        XCTAssertFalse(fs.isDirectory(sym))

        // isDirectory()
        XCTAssert(fs.isDirectory(AbsolutePath("/")))
        XCTAssert(!fs.isDirectory(AbsolutePath("/does-not-exist")))

        // getDirectoryContents()
        XCTAssertThrows(FileSystemError.noEntry) {
            _ = try fs.getDirectoryContents(AbsolutePath("/does-not-exist"))
        }
        let thisDirectoryContents = try! fs.getDirectoryContents(AbsolutePath(#file).parentDirectory).map {$0}
        XCTAssertTrue(!thisDirectoryContents.contains(where: { $0 == "." }))
        XCTAssertTrue(!thisDirectoryContents.contains(where: { $0 == ".." }))
        XCTAssertTrue(thisDirectoryContents.contains(where: { $0 == AbsolutePath(#file).basename }))
    }

    func testLocalCreateDirectory() throws {
        var fs = Basic.localFileSystem
        
        let tmpDir = try TemporaryDirectory(prefix: #function, removeTreeOnDeinit: true)
        do {
            let testPath = tmpDir.path.appending(component: "new-dir")
            XCTAssert(!fs.exists(testPath))
            try! fs.createDirectory(testPath)
            XCTAssert(fs.exists(testPath))
            XCTAssert(fs.isDirectory(testPath))
        }

        do {
            let testPath = tmpDir.path.appending(components: "another-new-dir", "with-a-subdir")
            XCTAssert(!fs.exists(testPath))
            try! fs.createDirectory(testPath, recursive: true)
            XCTAssert(fs.exists(testPath))
            XCTAssert(fs.isDirectory(testPath))
        }
    }

    func testLocalReadWriteFile() throws {
        var fs = Basic.localFileSystem
        
        let tmpDir = try TemporaryDirectory(prefix: #function, removeTreeOnDeinit: true)
        // Check read/write of a simple file.
        let testData = (0..<1000).map { $0.description }.joined(separator: ", ")
        let filePath = tmpDir.path.appending(component: "test-data.txt")
        try! fs.writeFileContents(filePath, bytes: ByteString(testData))
        XCTAssertTrue(fs.isFile(filePath))
        let data = try! fs.readFileContents(filePath)
        XCTAssertEqual(data, ByteString(testData))

        // Check overwrite of a file.
        try! fs.writeFileContents(filePath, bytes: "Hello, new world!")
        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, new world!")
    
        // Check read/write of a directory.
        XCTAssertThrows(FileSystemError.ioError) {
            _ = try fs.readFileContents(filePath.parentDirectory)
        }
        XCTAssertThrows(FileSystemError.isDirectory) {
            try fs.writeFileContents(filePath.parentDirectory, bytes: [])
        }
        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, new world!")
    
        // Check read/write against root.
        XCTAssertThrows(FileSystemError.ioError) {
            _ = try fs.readFileContents(AbsolutePath("/"))
        }
        XCTAssertThrows(FileSystemError.isDirectory) {
            try fs.writeFileContents(AbsolutePath("/"), bytes: [])
        }
        XCTAssert(fs.exists(filePath))
    
        // Check read/write into a non-directory.
        XCTAssertThrows(FileSystemError.notDirectory) {
            _ = try fs.readFileContents(filePath.appending(component: "not-possible"))
        }
        XCTAssertThrows(FileSystemError.notDirectory) {
            try fs.writeFileContents(filePath.appending(component: "not-possible"), bytes: [])
        }
        XCTAssert(fs.exists(filePath))
    
        // Check read/write into a missing directory.
        let missingDir = tmpDir.path.appending(components: "does", "not", "exist")
        XCTAssertThrows(FileSystemError.noEntry) {
            _ = try fs.readFileContents(missingDir)
        }
        XCTAssertThrows(FileSystemError.noEntry) {
            try fs.writeFileContents(missingDir, bytes: [])
        }
        XCTAssert(!fs.exists(missingDir))
    }

    // MARK: InMemoryFileSystem Tests

    func testInMemoryBasics() {
        let fs = InMemoryFileSystem()

        // exists()
        XCTAssert(!fs.exists(AbsolutePath("/does-not-exist")))

        // isDirectory()
        XCTAssert(!fs.isDirectory(AbsolutePath("/does-not-exist")))

        // isFile()
        XCTAssert(!fs.isFile(AbsolutePath("/does-not-exist")))

        // isSymlink()
        XCTAssert(!fs.isSymlink(AbsolutePath("/does-not-exist")))

        // getDirectoryContents()
        XCTAssertThrows(FileSystemError.noEntry) {
            _ = try fs.getDirectoryContents(AbsolutePath("/does-not-exist"))
        }

        // createDirectory()
        XCTAssert(!fs.isDirectory(AbsolutePath("/new-dir")))
        try! fs.createDirectory(AbsolutePath("/new-dir/subdir"), recursive: true)
        XCTAssert(fs.isDirectory(AbsolutePath("/new-dir")))
        XCTAssert(fs.isDirectory(AbsolutePath("/new-dir/subdir")))
    }

    func testInMemoryCreateDirectory() {
        let fs = InMemoryFileSystem()
        let subdir = AbsolutePath("/new-dir/subdir")
        try! fs.createDirectory(subdir, recursive: true)
        XCTAssert(fs.isDirectory(subdir))

        // Check duplicate creation.
        try! fs.createDirectory(subdir, recursive: true)
        XCTAssert(fs.isDirectory(subdir))
        
        // Check non-recursive subdir creation.
        let subsubdir = subdir.appending(component: "new-subdir")
        XCTAssert(!fs.isDirectory(subsubdir))
        try! fs.createDirectory(subsubdir, recursive: false)
        XCTAssert(fs.isDirectory(subsubdir))
        
        // Check non-recursive failing subdir case.
        let newsubdir = AbsolutePath("/very-new-dir/subdir")
        XCTAssert(!fs.isDirectory(newsubdir))
        XCTAssertThrows(FileSystemError.noEntry) {
            try fs.createDirectory(newsubdir, recursive: false)
        }
        XCTAssert(!fs.isDirectory(newsubdir))
        
        // Check directory creation over a file.
        let filePath = AbsolutePath("/mach_kernel")
        try! fs.writeFileContents(filePath, bytes: [0xCD, 0x0D])
        XCTAssert(fs.exists(filePath) && !fs.isDirectory(filePath))
        XCTAssertThrows(FileSystemError.notDirectory) {
            try fs.createDirectory(filePath, recursive: true)
        }
        XCTAssertThrows(FileSystemError.notDirectory) {
            try fs.createDirectory(filePath.appending(component: "not-possible"), recursive: true)
        }
        XCTAssert(fs.exists(filePath) && !fs.isDirectory(filePath))
    }
    
    func testInMemoryReadWriteFile() {
        let fs = InMemoryFileSystem()
        try! fs.createDirectory(AbsolutePath("/new-dir/subdir"), recursive: true)

        // Check read/write of a simple file.
        let filePath = AbsolutePath("/new-dir/subdir").appending(component: "new-file.txt")
        XCTAssert(!fs.exists(filePath))
        XCTAssertFalse(fs.isFile(filePath))
        try! fs.writeFileContents(filePath, bytes: "Hello, world!")
        XCTAssert(fs.exists(filePath))
        XCTAssertTrue(fs.isFile(filePath))
        XCTAssertFalse(fs.isSymlink(filePath))
        XCTAssert(!fs.isDirectory(filePath))
        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, world!")

        // Check overwrite of a file.
        try! fs.writeFileContents(filePath, bytes: "Hello, new world!")
        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, new world!")
        
        // Check read/write of a directory.
        XCTAssertThrows(FileSystemError.isDirectory) {
            _ = try fs.readFileContents(filePath.parentDirectory)
        }
        XCTAssertThrows(FileSystemError.isDirectory) {
            try fs.writeFileContents(filePath.parentDirectory, bytes: [])
        }
        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, new world!")
        
        // Check read/write against root.
        XCTAssertThrows(FileSystemError.isDirectory) {
            _ = try fs.readFileContents(AbsolutePath("/"))
        }
        XCTAssertThrows(FileSystemError.isDirectory) {
            try fs.writeFileContents(AbsolutePath("/"), bytes: [])
        }
        XCTAssert(fs.exists(filePath))
        XCTAssertTrue(fs.isFile(filePath))
        
        // Check read/write into a non-directory.
        XCTAssertThrows(FileSystemError.notDirectory) {
            _ = try fs.readFileContents(filePath.appending(component: "not-possible"))
        }
        XCTAssertThrows(FileSystemError.notDirectory) {
            try fs.writeFileContents(filePath.appending(component: "not-possible"), bytes: [])
        }
        XCTAssert(fs.exists(filePath))
        
        // Check read/write into a missing directory.
        let missingDir = AbsolutePath("/does/not/exist")
        XCTAssertThrows(FileSystemError.noEntry) {
            _ = try fs.readFileContents(missingDir)
        }
        XCTAssertThrows(FileSystemError.noEntry) {
            try fs.writeFileContents(missingDir, bytes: [])
        }
        XCTAssert(!fs.exists(missingDir))
    }

    // MARK: RootedFileSystem Tests

    func testRootedFileSystem() throws {
        // Create the test file system.
        var baseFileSystem = InMemoryFileSystem() as FileSystem
        try baseFileSystem.createDirectory(AbsolutePath("/base/rootIsHere/subdir"), recursive: true)
        try baseFileSystem.writeFileContents(AbsolutePath("/base/rootIsHere/subdir/file"), bytes: "Hello, world!")

        // Create the rooted file system.
        var rerootedFileSystem = RerootedFileSystemView(&baseFileSystem, rootedAt: AbsolutePath("/base/rootIsHere"))

        // Check that it has the appropriate view.
        XCTAssert(rerootedFileSystem.exists(AbsolutePath("/subdir")))
        XCTAssert(rerootedFileSystem.isDirectory(AbsolutePath("/subdir")))
        XCTAssert(rerootedFileSystem.exists(AbsolutePath("/subdir/file")))
        XCTAssertEqual(try rerootedFileSystem.readFileContents(AbsolutePath("/subdir/file")), "Hello, world!")

        // Check that mutations work appropriately.
        XCTAssert(!baseFileSystem.exists(AbsolutePath("/base/rootIsHere/subdir2")))
        try rerootedFileSystem.createDirectory(AbsolutePath("/subdir2"))
        XCTAssert(baseFileSystem.isDirectory(AbsolutePath("/base/rootIsHere/subdir2")))
    }
    
    static var allTests = [
        ("testLocalBasics", testLocalBasics),
        ("testLocalCreateDirectory", testLocalCreateDirectory),
        ("testLocalReadWriteFile", testLocalReadWriteFile),
        ("testInMemoryBasics", testInMemoryBasics),
        ("testInMemoryCreateDirectory", testInMemoryCreateDirectory),
        ("testInMemoryReadWriteFile", testInMemoryReadWriteFile),
        ("testRootedFileSystem", testRootedFileSystem),
    ]
}
