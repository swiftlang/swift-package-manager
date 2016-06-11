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

func XCTAssertThrows<T where T: ErrorProtocol, T: Equatable>(_ expectedError: T, file: StaticString = #file, line: UInt = #line, _ body: () throws -> ()) {
    do {
        try body()
        XCTFail("body completed successfully", file: file, line: line)
    } catch let error as T {
        XCTAssertEqual(error, expectedError)
    } catch {
        XCTFail("unexpected error thrown", file: file, line: line)
    }
}

class FSProxyTests: XCTestCase {

    // MARK: LocalFS Tests

    func testLocalBasics() {
        let fs = Basic.localFS

        // exists()
        XCTAssert(fs.exists("/"))
        XCTAssert(!fs.exists("/does-not-exist"))

        // isDirectory()
        XCTAssert(fs.isDirectory("/"))
        XCTAssert(!fs.isDirectory("/does-not-exist"))

        // getDirectoryContents()
        XCTAssertThrows(FSProxyError.noEntry) {
            _ = try fs.getDirectoryContents("/does-not-exist")
        }
        let thisDirectoryContents = try! fs.getDirectoryContents(#file.parentDirectory)
        XCTAssertTrue(!thisDirectoryContents.contains({ $0 == "." }))
        XCTAssertTrue(!thisDirectoryContents.contains({ $0 == ".." }))
        XCTAssertTrue(thisDirectoryContents.contains({ $0 == #file.basename }))
    }

    func testLocalCreateDirectory() {
        var fs = Basic.localFS
        
        // FIXME: Migrate to temporary file wrapper, once we have one.
        try! POSIX.mkdtemp(#function) { tmpDir in
            do {
                let testPath = Path.join(tmpDir, "new-dir")
                XCTAssert(!fs.exists(testPath))
                try! fs.createDirectory(testPath)
                XCTAssert(fs.exists(testPath))
                XCTAssert(fs.isDirectory(testPath))
            }

            do {
                let testPath = Path.join(tmpDir, "another-new-dir/with-a-subdir")
                XCTAssert(!fs.exists(testPath))
                try! fs.createDirectory(testPath, recursive: true)
                XCTAssert(fs.exists(testPath))
                XCTAssert(fs.isDirectory(testPath))
            }

            try! Utility.removeFileTree(tmpDir)
        }
    }

    // MARK: PseudoFS Tests

    func testPseudoBasics() {
        let fs = PseudoFS()

        // exists()
        XCTAssert(!fs.exists("/does-not-exist"))

        // isDirectory()
        XCTAssert(!fs.isDirectory("/does-not-exist"))

        // getDirectoryContents()
        XCTAssertThrows(FSProxyError.noEntry) {
            _ = try fs.getDirectoryContents("/does-not-exist")
        }

        // createDirectory()
        XCTAssert(!fs.isDirectory("/new-dir"))
        try! fs.createDirectory("/new-dir/subdir", recursive: true)
        XCTAssert(fs.isDirectory("/new-dir"))
        XCTAssert(fs.isDirectory("/new-dir/subdir"))
    }

    func testPseudoCreateDirectory() {
        let fs = PseudoFS()
        let subdir = "/new-dir/subdir"
        try! fs.createDirectory(subdir, recursive: true)
        XCTAssert(fs.isDirectory(subdir))

        // Check duplicate creation.
        try! fs.createDirectory(subdir, recursive: true)
        XCTAssert(fs.isDirectory(subdir))
        
        // Check non-recursive subdir creation.
        let subsubdir = Path.join(subdir, "new-subdir")
        XCTAssert(!fs.isDirectory(subsubdir))
        try! fs.createDirectory(subsubdir, recursive: false)
        XCTAssert(fs.isDirectory(subsubdir))
        
        // Check non-recursive failing subdir case.
        let newsubdir = "/very-new-dir/subdir"
        XCTAssert(!fs.isDirectory(newsubdir))
        XCTAssertThrows(FSProxyError.noEntry) {
            try fs.createDirectory(newsubdir, recursive: false)
        }
        XCTAssert(!fs.isDirectory(newsubdir))
        
        // FIXME: Need to check directory creation over a file, once we can create files.
    }
    
    static var allTests = [
        ("testLocalBasics", testLocalBasics),
        ("testLocalCreateDirectory", testLocalCreateDirectory),
        ("testPseudoBasics", testPseudoBasics),
        ("testPseudoCreateDirectory", testPseudoCreateDirectory),
    ]
}
