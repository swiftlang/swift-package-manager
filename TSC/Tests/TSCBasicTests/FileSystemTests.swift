/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCTestSupport
import TSCLibc

class FileSystemTests: XCTestCase {

    // MARK: LocalFS Tests

    func testLocalBasics() throws {
        let fs = TSCBasic.localFileSystem
        try! withTemporaryFile { file in
            try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
                // exists()
                XCTAssert(fs.exists(AbsolutePath("/")))
                XCTAssert(!fs.exists(AbsolutePath("/does-not-exist")))

                // isFile()
                XCTAssertTrue(fs.exists(file.path))
                XCTAssertTrue(fs.isFile(file.path))
                XCTAssertEqual(try fs.getFileInfo(file.path).fileType, .typeRegular)
                XCTAssertFalse(fs.isDirectory(file.path))
                XCTAssertFalse(fs.isFile(AbsolutePath("/does-not-exist")))
                XCTAssertFalse(fs.isSymlink(AbsolutePath("/does-not-exist")))
                XCTAssertThrowsError(try fs.getFileInfo(AbsolutePath("/does-not-exist")))

                // isSymlink()
                let sym = tempDirPath.appending(component: "hello")
                try! createSymlink(sym, pointingAt: file.path)
                XCTAssertTrue(fs.isSymlink(sym))
                XCTAssertTrue(fs.isFile(sym))
                XCTAssertEqual(try fs.getFileInfo(sym).fileType, .typeSymbolicLink)
                XCTAssertFalse(fs.isDirectory(sym))

                // isExecutableFile
                let executable = tempDirPath.appending(component: "exec-foo")
                let executableSym = tempDirPath.appending(component: "exec-sym")
                try! createSymlink(executableSym, pointingAt: executable)
                let stream = BufferedOutputByteStream()
                stream <<< """
                    #!/bin/sh
                    set -e
                    exit

                    """
                try! localFileSystem.writeFileContents(executable, bytes: stream.bytes)
                try! Process.checkNonZeroExit(args: "chmod", "+x", executable.pathString)
                XCTAssertTrue(fs.isExecutableFile(executable))
                XCTAssertTrue(fs.isExecutableFile(executableSym))
                XCTAssertTrue(fs.isSymlink(executableSym))
                XCTAssertFalse(fs.isExecutableFile(sym))
                XCTAssertFalse(fs.isExecutableFile(file.path))
                XCTAssertFalse(fs.isExecutableFile(AbsolutePath("/does-not-exist")))
                XCTAssertFalse(fs.isExecutableFile(AbsolutePath("/")))

                // isDirectory()
                XCTAssert(fs.isDirectory(AbsolutePath("/")))
                XCTAssert(!fs.isDirectory(AbsolutePath("/does-not-exist")))

                // getDirectoryContents()
                do {
                    _ = try fs.getDirectoryContents(AbsolutePath("/does-not-exist"))
                    XCTFail("Unexpected success")
                } catch {
                    XCTAssertEqual(error.localizedDescription, "The folder “does-not-exist” doesn’t exist.")
                }

                let thisDirectoryContents = try! fs.getDirectoryContents(AbsolutePath(#file).parentDirectory)
                XCTAssertTrue(!thisDirectoryContents.contains(where: { $0 == "." }))
                XCTAssertTrue(!thisDirectoryContents.contains(where: { $0 == ".." }))
                XCTAssertTrue(thisDirectoryContents.contains(where: { $0 == AbsolutePath(#file).basename }))
            }
        }
    }

    func testLocalExistsSymlink() throws {
        mktmpdir { path in
            let fs = TSCBasic.localFileSystem

            let source = path.appending(component: "source")
            let target = path.appending(component: "target")
            try fs.writeFileContents(target, bytes: "source")

            // Source and target exist.

            try createSymlink(source, pointingAt: target)
            XCTAssertEqual(fs.exists(source), true)
            XCTAssertEqual(fs.exists(source, followSymlink: true), true)
            XCTAssertEqual(fs.exists(source, followSymlink: false), true)

            // Source only exists.

            try fs.removeFileTree(target)
            XCTAssertEqual(fs.exists(source), false)
            XCTAssertEqual(fs.exists(source, followSymlink: true), false)
            XCTAssertEqual(fs.exists(source, followSymlink: false), true)

            // None exist.

            try fs.removeFileTree(source)
            XCTAssertEqual(fs.exists(source), false)
            XCTAssertEqual(fs.exists(source, followSymlink: true), false)
            XCTAssertEqual(fs.exists(source, followSymlink: false), false)
        }
    }

    func testLocalCreateDirectory() throws {
        let fs = TSCBasic.localFileSystem

        try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { tmpDirPath in
            do {
                let testPath = tmpDirPath.appending(component: "new-dir")
                XCTAssert(!fs.exists(testPath))
                try fs.createDirectory(testPath)
                try fs.createDirectory(testPath)
                XCTAssert(fs.exists(testPath))
                XCTAssert(fs.isDirectory(testPath))
            }

            do {
                let testPath = tmpDirPath.appending(components: "another-new-dir", "with-a-subdir")
                XCTAssert(!fs.exists(testPath))
                try fs.createDirectory(testPath, recursive: true)
                XCTAssert(fs.exists(testPath))
                XCTAssert(fs.isDirectory(testPath))
            }
        }
    }

    func testLocalReadWriteFile() throws {
        let fs = TSCBasic.localFileSystem

        try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { tmpDirPath in
            // Check read/write of a simple file.
            let testData = (0..<1000).map { $0.description }.joined(separator: ", ")
            let filePath = tmpDirPath.appending(component: "test-data.txt")
            try! fs.writeFileContents(filePath, bytes: ByteString(testData))
            XCTAssertTrue(fs.isFile(filePath))
            let data = try! fs.readFileContents(filePath)
            XCTAssertEqual(data, ByteString(testData))

            // Atomic writes
            let inMemoryFilePath = AbsolutePath("/file.text")
            XCTAssertNoThrow(try TSCBasic.InMemoryFileSystem(files: [:]).writeFileContents(inMemoryFilePath, bytes: ByteString(testData), atomically: true))
            XCTAssertNoThrow(try TSCBasic.InMemoryFileSystem(files: [:]).writeFileContents(inMemoryFilePath, bytes: ByteString(testData), atomically: false))
            // Local file system does support atomic writes, so it doesn't throw.
            let byteString = ByteString(testData)
            let filePath1 = tmpDirPath.appending(components: "test-data-1.txt")
            XCTAssertNoThrow(try fs.writeFileContents(filePath1, bytes: byteString, atomically: false))
            let read1 = try fs.readFileContents(filePath1)
            XCTAssertEqual(read1, byteString)

            // Test overwriting file non-atomically
            XCTAssertNoThrow(try fs.writeFileContents(filePath1, bytes: byteString, atomically: false))

            let filePath2 = tmpDirPath.appending(components: "test-data-2.txt")
            XCTAssertNoThrow(try fs.writeFileContents(filePath2, bytes: byteString, atomically: true))
            let read2 = try fs.readFileContents(filePath2)
            XCTAssertEqual(read2, byteString)

            // Test overwriting file atomically
            XCTAssertNoThrow(try fs.writeFileContents(filePath2, bytes: byteString, atomically: true))

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
              #if os(Android)
                _ = try fs.readFileContents(AbsolutePath("/system/"))
              #else
                _ = try fs.readFileContents(AbsolutePath("/"))
              #endif
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
            let missingDir = tmpDirPath.appending(components: "does", "not", "exist")
            XCTAssertThrows(FileSystemError.noEntry) {
                _ = try fs.readFileContents(missingDir)
            }
            XCTAssertThrows(FileSystemError.noEntry) {
                try fs.writeFileContents(missingDir, bytes: [])
            }
            XCTAssert(!fs.exists(missingDir))
        }
    }

    func testRemoveFileTree() throws {
        mktmpdir { path in
            try removeFileTreeTester(fs: localFileSystem, basePath: path)
        }
    }

    func testCopyAndMoveItem() throws {
        let fs = TSCBasic.localFileSystem

        mktmpdir { path in
            let source = path.appending(component: "source")
            let destination = path.appending(component: "destination")

            // Copy with no source

            XCTAssertThrows(FileSystemError.noEntry) {
                try fs.copy(from: source, to: destination)
            }
            XCTAssertThrows(FileSystemError.noEntry) {
                try fs.move(from: source, to: destination)
            }

            // Copy with a file at destination

            try fs.writeFileContents(source, bytes: "source1")
            try fs.writeFileContents(destination, bytes: "destination")

            XCTAssertThrows(FileSystemError.alreadyExistsAtDestination) {
                try fs.copy(from: source, to: destination)
            }
            XCTAssertThrows(FileSystemError.alreadyExistsAtDestination) {
                try fs.move(from: source, to: destination)
            }

            // Copy file

            try fs.removeFileTree(destination)

            XCTAssertNoThrow(try fs.copy(from: source, to: destination))
            XCTAssert(fs.exists(source))
            XCTAssertEqual(try fs.readFileContents(destination).cString, "source1")

            // Move file

            try fs.removeFileTree(destination)
            try fs.writeFileContents(source, bytes: "source2")

            XCTAssertNoThrow(try fs.move(from: source, to: destination))
            XCTAssert(!fs.exists(source))
            XCTAssertEqual(try fs.readFileContents(destination).cString, "source2")

            let sourceChild = source.appending(component: "child")
            let destinationChild = destination.appending(component: "child")

            // Copy directory

            try fs.createDirectory(source)
            try fs.writeFileContents(sourceChild, bytes: "source3")
            try fs.removeFileTree(destination)

            XCTAssertNoThrow(try fs.copy(from: source, to: destination))
            XCTAssertEqual(try fs.readFileContents(destinationChild).cString, "source3")

            // Move directory

            try fs.writeFileContents(sourceChild, bytes: "source4")
            try fs.removeFileTree(destination)

            XCTAssertNoThrow(try fs.move(from: source, to: destination))
            XCTAssert(!fs.exists(source))
            XCTAssertEqual(try fs.readFileContents(destinationChild).cString, "source4")

            // Copy to non-existant folder

            try fs.writeFileContents(source, bytes: "source3")
            try fs.removeFileTree(destination)

            XCTAssertThrowsError(try fs.copy(from: source, to: destinationChild))
            XCTAssertThrowsError(try fs.move(from: source, to: destinationChild))
        }
    }

    // MARK: InMemoryFileSystem Tests

    func testInMemoryBasics() throws {
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
        try fs.createDirectory(AbsolutePath("/new-dir/subdir"), recursive: true)
        XCTAssert(fs.isDirectory(AbsolutePath("/new-dir")))
        XCTAssert(fs.isDirectory(AbsolutePath("/new-dir/subdir")))
        XCTAssertEqual(try fs.getDirectoryContents(AbsolutePath("/")), ["new-dir"])
        XCTAssertEqual(try fs.getDirectoryContents(AbsolutePath("/new-dir")), ["subdir"])
    }

    func testInMemoryCreateDirectory() {
        let fs = InMemoryFileSystem()
        // Make sure root entry isn't created.
        try! fs.createDirectory(AbsolutePath("/"), recursive: true)
        let rootContents = try! fs.getDirectoryContents(.root)
        XCTAssertEqual(rootContents, [])

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

    func testInMemoryFsCopy() throws {
        let fs = InMemoryFileSystem()
        try! fs.createDirectory(AbsolutePath("/new-dir/subdir"), recursive: true)
        let filePath = AbsolutePath("/new-dir/subdir").appending(component: "new-file.txt")
        try! fs.writeFileContents(filePath, bytes: "Hello, world!")
        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, world!")

        let copyFs = fs.copy()
        XCTAssertEqual(try! copyFs.readFileContents(filePath), "Hello, world!")
        try! copyFs.writeFileContents(filePath, bytes: "Hello, world 2!")

        XCTAssertEqual(try! fs.readFileContents(filePath), "Hello, world!")
        XCTAssertEqual(try! copyFs.readFileContents(filePath), "Hello, world 2!")
    }

    func testInMemRemoveFileTree() throws {
        let fs = InMemoryFileSystem() as FileSystem
        try removeFileTreeTester(fs: fs, basePath: .root)
    }

    func testInMemCopyAndMoveItem() throws {
        let fs = InMemoryFileSystem()
        let path = AbsolutePath("/tmp")
        try fs.createDirectory(path)
        let source = path.appending(component: "source")
        let destination = path.appending(component: "destination")

        // Copy with no source

        XCTAssertThrows(FileSystemError.noEntry) {
            try fs.copy(from: source, to: destination)
        }
        XCTAssertThrows(FileSystemError.noEntry) {
            try fs.move(from: source, to: destination)
        }

        // Copy with a file at destination

        try fs.writeFileContents(source, bytes: "source1")
        try fs.writeFileContents(destination, bytes: "destination")

        XCTAssertThrows(FileSystemError.alreadyExistsAtDestination) {
            try fs.copy(from: source, to: destination)
        }
        XCTAssertThrows(FileSystemError.alreadyExistsAtDestination) {
            try fs.move(from: source, to: destination)
        }

        // Copy file

        try fs.removeFileTree(destination)

        XCTAssertNoThrow(try fs.copy(from: source, to: destination))
        XCTAssert(fs.exists(source))
        XCTAssertEqual(try fs.readFileContents(destination).cString, "source1")

        // Move file

        try fs.removeFileTree(destination)
        try fs.writeFileContents(source, bytes: "source2")

        XCTAssertNoThrow(try fs.move(from: source, to: destination))
        XCTAssert(!fs.exists(source))
        XCTAssertEqual(try fs.readFileContents(destination).cString, "source2")

        let sourceChild = source.appending(component: "child")
        let destinationChild = destination.appending(component: "child")

        // Copy directory

        try fs.createDirectory(source)
        try fs.writeFileContents(sourceChild, bytes: "source3")
        try fs.removeFileTree(destination)

        XCTAssertNoThrow(try fs.copy(from: source, to: destination))
        XCTAssertEqual(try fs.readFileContents(destinationChild).cString, "source3")

        // Move directory

        try fs.writeFileContents(sourceChild, bytes: "source4")
        try fs.removeFileTree(destination)

        XCTAssertNoThrow(try fs.move(from: source, to: destination))
        XCTAssert(!fs.exists(source))
        XCTAssertEqual(try fs.readFileContents(destinationChild).cString, "source4")

        // Copy to non-existant folder

        try fs.writeFileContents(source, bytes: "source3")
        try fs.removeFileTree(destination)

        XCTAssertThrowsError(try fs.copy(from: source, to: destinationChild))
        XCTAssertThrowsError(try fs.move(from: source, to: destinationChild))
    }

    // MARK: RootedFileSystem Tests

    func testRootedFileSystem() throws {
        // Create the test file system.
        let baseFileSystem = InMemoryFileSystem() as FileSystem
        try baseFileSystem.createDirectory(AbsolutePath("/base/rootIsHere/subdir"), recursive: true)
        try baseFileSystem.writeFileContents(AbsolutePath("/base/rootIsHere/subdir/file"), bytes: "Hello, world!")

        // Create the rooted file system.
        let rerootedFileSystem = RerootedFileSystemView(baseFileSystem, rootedAt: AbsolutePath("/base/rootIsHere"))

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

    func testSetAttribute() throws {
      #if os(macOS) || os(Linux) || os(Android)
        mktmpdir { path in
            let fs = TSCBasic.localFileSystem

            let dir = path.appending(component: "dir")
            let foo = dir.appending(component: "foo")
            let bar = dir.appending(component: "bar")
            let sym = dir.appending(component: "sym")

            try fs.createDirectory(dir, recursive: true)
            try fs.writeFileContents(foo, bytes: "")
            try fs.writeFileContents(bar, bytes: "")
            try createSymlink(sym, pointingAt: foo)

            // Set foo to unwritable.
            try fs.chmod(.userUnWritable, path: foo)
            XCTAssertThrows(FileSystemError.invalidAccess) {
                try fs.writeFileContents(foo, bytes: "test")
            }

            // Set the directory as unwritable.
            try fs.chmod(.userUnWritable, path: dir, options: [.recursive, .onlyFiles])
            XCTAssertThrows(FileSystemError.invalidAccess) {
                try fs.writeFileContents(bar, bytes: "test")
            }

            // Ensure we didn't modify foo's permission through the symlink.
            XCTAssertFalse(fs.isExecutableFile(foo))

            // It should be possible to add files.
            try fs.writeFileContents(dir.appending(component: "new"), bytes: "")

            // But not anymore.
            try fs.chmod(.userUnWritable, path: dir, options: [.recursive])
            XCTAssertThrows(FileSystemError.invalidAccess) {
                try fs.writeFileContents(dir.appending(component: "new2"), bytes: "")
            }

            try? fs.removeFileTree(bar)
            try? fs.removeFileTree(dir)
            XCTAssertTrue(fs.exists(dir))
            XCTAssertTrue(fs.exists(bar))

            // Set the entire directory as writable.
            try fs.chmod(.userWritable, path: dir, options: [.recursive])
            try fs.writeFileContents(foo, bytes: "test")
            try fs.removeFileTree(dir)
            XCTAssertFalse(fs.exists(dir))
        }
      #endif
    }
}

/// Helper method to test file tree removal method on the given file system.
///
/// - Parameters:
///   - fs: The filesystem to test on.
///   - basePath: The path at which the temporary file strucutre should be created.
private func removeFileTreeTester(fs: FileSystem, basePath path: AbsolutePath, file: StaticString = #file, line: UInt = #line) throws {
    // Test removing folders.
    let folders = path.appending(components: "foo", "bar", "baz")
    try fs.createDirectory(folders, recursive: true)
    XCTAssert(fs.exists(folders), file: file, line: line)
    try fs.removeFileTree(folders)
    XCTAssertFalse(fs.exists(folders), file: file, line: line)

    // Test removing file.
    let filePath = folders.appending(component: "foo.txt")
    try fs.createDirectory(folders, recursive: true)
    try fs.writeFileContents(filePath, bytes: "foo")
    XCTAssert(fs.exists(filePath), file: file, line: line)
    try fs.removeFileTree(filePath)
    XCTAssertFalse(fs.exists(filePath), file: file, line: line)
}
