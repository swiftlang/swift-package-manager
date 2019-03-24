/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class POSIXTests : XCTestCase {

    func testFileStatus() throws {
        let file = try TemporaryFile()
        XCTAssertTrue(localFileSystem.exists(file.path))
        XCTAssertTrue(localFileSystem.isFile(file.path))
        XCTAssertFalse(localFileSystem.isDirectory(file.path))

        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        XCTAssertTrue(localFileSystem.exists(dir.path))
        XCTAssertFalse(localFileSystem.isFile(dir.path))
        XCTAssertTrue(localFileSystem.isDirectory(dir.path))

        let sym = dir.path.appending(component: "hello")
        try createSymlink(sym, pointingAt: file.path)
        XCTAssertTrue(localFileSystem.exists(sym))
        XCTAssertTrue(localFileSystem.isFile(sym))
        XCTAssertFalse(localFileSystem.isDirectory(sym))

        let dir2 = try TemporaryDirectory(removeTreeOnDeinit: true)
        let dirSym = dir.path.appending(component: "dir2")
        try createSymlink(dirSym, pointingAt: dir2.path)
        XCTAssertTrue(localFileSystem.exists(dirSym))
        XCTAssertFalse(localFileSystem.isFile(dirSym))
        XCTAssertTrue(localFileSystem.isDirectory(dirSym))
    }
}
