/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import sys
import POSIX
import XCTest
import libc

class RmtreeTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testDoesNotFollowSymlinks", testDoesNotFollowSymlinks),
        ]
    }

    func testDoesNotFollowSymlinks() {
        do {
            try mkdtemp("foo") { root in
                let root = try realpath(root)

                try mkdir(root, "foo")
                try mkdir(root, "bar")
                try mkdir(root, "bar/baz")
                try mkdir(root, "bar/baz/goo")
                try symlink(create: "\(root)/foo/symlink", pointingAt: "\(root)/bar", relativeTo: root)

                XCTAssertTrue("\(root)/foo/symlink".isSymlink)
                XCTAssertEqual(try! realpath("\(root)/foo/symlink"), "\(root)/bar")
                XCTAssertTrue(try! realpath("\(root)/foo/symlink/baz").isDirectory)

                try rmtree(root, "foo")

                XCTAssertFalse("\(root)/foo".exists)
                XCTAssertFalse("\(root)/foo".isDirectory)
                XCTAssertTrue("\(root)/bar/baz".isDirectory)
                XCTAssertTrue("\(root)/bar/baz/goo".isDirectory)
            }
        } catch {
            XCTFail("\(error)")
        }
    }
}
