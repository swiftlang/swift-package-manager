/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import Basic
import POSIX
import Utility

class RmtreeTests: XCTestCase {
    func testDoesNotFollowSymlinks() {
        mktmpdir { root in
            let root = try realpath(root)  // FIXME: it would be better to not need this, but we end up relying on /tmp -> /private/tmp.
            
            try Utility.makeDirectories(root.appending("foo").asString)
            try Utility.makeDirectories(root.appending("bar/baz/goo").asString)
            try symlink(create: root.appending("foo/symlink").asString, pointingAt: root.appending("bar").asString, relativeTo: root.asString)
            
            XCTAssertTrue(try! isSymlink(root.appending("foo").appending("symlink")))
            XCTAssertEqual(try! realpath(root.appending("foo").appending("symlink")), root.appending("bar"))
            XCTAssertTrue(try! isDirectory(realpath(root.appending("foo").appending("symlink").appending("baz"))))

            try remove(root.appending("foo"))

            XCTAssertFalse(try! exists(root.appending("foo")))
            XCTAssertFalse(try! isDirectory(root.appending("foo")))
            XCTAssertTrue(try! isDirectory(root.appending("bar").appending("baz")))
            XCTAssertTrue(try! isDirectory(root.appending("bar").appending("baz").appending("goo")))
        }
    }

    static var allTests = [
        ("testDoesNotFollowSymlinks", testDoesNotFollowSymlinks),
    ]
}
