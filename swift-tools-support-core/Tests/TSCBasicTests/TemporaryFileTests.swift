/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import class Foundation.FileManager

import TSCBasic

class TemporaryFileTests: XCTestCase {
    func testBasicReadWrite() throws {
        let filePath: AbsolutePath = try withTemporaryFile(prefix: "myprefix", suffix: "mysuffix") { file in
            // Make sure the filename contains our prefix and suffix.
            XCTAssertTrue(file.path.basename.hasPrefix("myprefix"))
            XCTAssertTrue(file.path.basename.hasSuffix("mysuffix"))

            // Check if file is created.
            XCTAssertTrue(localFileSystem.isFile(file.path))

            // Try writing some data to the file.
            let stream = BufferedOutputByteStream()
            stream <<< "foo"
            stream <<< "bar"
            stream <<< "baz"
            try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)

            // Go to the beginning of the file.
            file.fileHandle.seek(toFileOffset: 0)
            // Read the contents.
            let contents = try localFileSystem.readFileContents(file.path)
            XCTAssertEqual(contents, "foobarbaz")

            return file.path
        }
        // File should be deleted now.
        XCTAssertFalse(localFileSystem.isFile(filePath))
    }
    
    func testNoCleanupTemporaryFile() throws {
        let filePath: AbsolutePath = try withTemporaryFile(deleteOnClose:false) { file in
            // Check if file is created.
            XCTAssertTrue(localFileSystem.isFile(file.path))
            
            // Try writing some data to the file.
            let stream = BufferedOutputByteStream()
            stream <<< "foo"
            stream <<< "bar"
            stream <<< "baz"
            try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)
            
            // Go to the beginning of the file.
            file.fileHandle.seek(toFileOffset: 0)
            // Read the contents.
            let contents = try localFileSystem.readFileContents(file.path)
            XCTAssertEqual(contents, "foobarbaz")
            
            return file.path
        }
        // File should not be deleted.
        XCTAssertTrue(localFileSystem.isFile(filePath))
        // Delete the file now
        try localFileSystem.removeFileTree(filePath)
    }

    func testCanCreateUniqueTempFiles() throws {
        let (filePathOne, filePathTwo): (AbsolutePath, AbsolutePath) = try withTemporaryFile { fileOne in
          let filePathTwo: AbsolutePath = try withTemporaryFile { fileTwo in
              // Check files exists.
              XCTAssertTrue(localFileSystem.isFile(fileOne.path))
              XCTAssertTrue(localFileSystem.isFile(fileTwo.path))
              // Their paths should be different.
              XCTAssertTrue(fileOne.path != fileTwo.path)
              return fileTwo.path
          }
          return (fileOne.path, filePathTwo)
        }
        XCTAssertFalse(localFileSystem.isFile(filePathOne))
        XCTAssertFalse(localFileSystem.isFile(filePathTwo))
    }
    
    func testNonStandardASCIIName() throws {
        try withTemporaryFile(prefix: "Héllo") { file in
            XCTAssertTrue(localFileSystem.isFile(file.path))
        }
    }

    func testBasicTemporaryDirectory() throws {
        // Test can create and remove temp directory.
        let path1: AbsolutePath = try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            XCTAssertTrue(localFileSystem.isDirectory(tempDirPath))
            return tempDirPath
        }
        XCTAssertFalse(localFileSystem.isDirectory(path1))

        // Test temp directory is not removed when its not empty. 
        let path2: AbsolutePath = try withTemporaryDirectory { tempDirPath in
            XCTAssertTrue(localFileSystem.isDirectory(tempDirPath))
            // Create a file inside the temp directory.
            let filePath = tempDirPath.appending(component: "somefile")
            try localFileSystem.writeFileContents(filePath, bytes: ByteString())
            return tempDirPath
        }
        XCTAssertTrue(localFileSystem.isDirectory(path2))
        // Cleanup.
        try FileManager.default.removeItem(atPath: path2.pathString)
        XCTAssertFalse(localFileSystem.isDirectory(path2))

        // Test temp directory is removed when its not empty and removeTreeOnDeinit is enabled.
        let path3: AbsolutePath = try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            XCTAssertTrue(localFileSystem.isDirectory(tempDirPath))
            let filePath = tempDirPath.appending(component: "somefile")
            try localFileSystem.writeFileContents(filePath, bytes: ByteString())
            return tempDirPath
        }
        XCTAssertFalse(localFileSystem.isDirectory(path3))
    }

    func testCanCreateUniqueTempDirectories() throws {
        let (pathOne, pathTwo): (AbsolutePath, AbsolutePath) = try withTemporaryDirectory(removeTreeOnDeinit: true) { pathOne in
            let pathTwo: AbsolutePath = try withTemporaryDirectory(removeTreeOnDeinit: true) { pathTwo in
                XCTAssertTrue(localFileSystem.isDirectory(pathOne))
                XCTAssertTrue(localFileSystem.isDirectory(pathTwo))
                // Their paths should be different.
                XCTAssertTrue(pathOne != pathTwo)
                return pathTwo
            }
            return (pathOne, pathTwo)
        }
        XCTAssertFalse(localFileSystem.isDirectory(pathOne))
        XCTAssertFalse(localFileSystem.isDirectory(pathTwo))
    }

    /// Check that the temporary file doesn't leak file descriptors.
    func testLeaks() throws {
        // We check this by testing that we get back the same FD after a
        // sequence of creating and destroying TemporaryFile objects. I don't
        // believe that this is guaranteed by POSIX, but it is true on all
        // platforms I know of.
        let initialFD = try Int(withTemporaryFile { return $0.fileHandle.fileDescriptor })
        for _ in 0..<10 {
            _ = try withTemporaryFile { return $0.fileHandle }
        }
        let endFD = try Int(withTemporaryFile { return $0.fileHandle.fileDescriptor })
        XCTAssertEqual(initialFD, endFD)
    }
}
