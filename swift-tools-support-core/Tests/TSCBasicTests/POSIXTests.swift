/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic

class POSIXTests : XCTestCase {

    func testFileStatus() throws {
        try withTemporaryFile { file in
            XCTAssertTrue(localFileSystem.exists(file.path))
            XCTAssertTrue(localFileSystem.isFile(file.path))
            XCTAssertFalse(localFileSystem.isDirectory(file.path))

            try withTemporaryDirectory(removeTreeOnDeinit: true) { dirPath in
                XCTAssertTrue(localFileSystem.exists(dirPath))
                XCTAssertFalse(localFileSystem.isFile(dirPath))
                XCTAssertTrue(localFileSystem.isDirectory(dirPath))

                let sym = dirPath.appending(component: "hello")
                try createSymlink(sym, pointingAt: file.path)
                XCTAssertTrue(localFileSystem.exists(sym))
                XCTAssertTrue(localFileSystem.isFile(sym))
                XCTAssertFalse(localFileSystem.isDirectory(sym))

                try withTemporaryDirectory(removeTreeOnDeinit: true) { dir2Path in
                    let dirSym = dirPath.appending(component: "dir2")
                    try createSymlink(dirSym, pointingAt: dir2Path)
                    XCTAssertTrue(localFileSystem.exists(dirSym))
                    XCTAssertFalse(localFileSystem.isFile(dirSym))
                    XCTAssertTrue(localFileSystem.isDirectory(dirSym))
                }
            }
        }
    }
}
