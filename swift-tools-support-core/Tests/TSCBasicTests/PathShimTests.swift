/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest

import TSCBasic

class PathShimTests : XCTestCase {
    
    func testRescursiveDirectoryCreation() {
        // For the tests we'll need a temporary directory.
        try! withTemporaryDirectory(removeTreeOnDeinit: true) { path in
            // Create a directory under several ancestor directories.
            let dirPath = path.appending(components: "abc", "def", "ghi", "mno", "pqr")
            try! makeDirectories(dirPath)

            // Check that we were able to actually create the directory.
            XCTAssertTrue(localFileSystem.isDirectory(dirPath))

            // Check that there's no error if we try to create the directory again.
            try! makeDirectories(dirPath)
        }
    }
}

class WalkTests : XCTestCase {

    func testNonRecursive() {
      #if os(Android)
        let root = "/system"
        var expected = [
            AbsolutePath("\(root)/usr"),
            AbsolutePath("\(root)/bin"),
            AbsolutePath("\(root)/xbin")
        ]
      #else
        let root = ""
        var expected = [
            AbsolutePath("/usr"),
            AbsolutePath("/bin"),
            AbsolutePath("/sbin")
        ]
      #endif
        for x in try! walk(AbsolutePath("\(root)/"), recursively: false) {
            if let i = expected.firstIndex(of: x) {
                expected.remove(at: i)
            }
          #if os(Android)
            XCTAssertEqual(3, x.components.count)
          #else
            XCTAssertEqual(2, x.components.count)
          #endif
        }
        XCTAssertEqual(expected.count, 0)
    }

    func testRecursive() {
        let root = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory.appending(component: "Sources")
        var expected = [
            root.appending(component: "TSCBasic"),
            root.appending(component: "TSCUtility")
        ]
        for x in try! walk(root) {
            if let i = expected.firstIndex(of: x) {
                expected.remove(at: i)
            }
        }
        XCTAssertEqual(expected, [])
    }
}
