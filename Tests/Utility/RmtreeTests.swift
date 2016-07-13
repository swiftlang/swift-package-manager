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
        do {
            try mkdtemp("foo") { root in
                let root = try realpath(root)  // FIXME: it would be better to not need this, but we end up relying on /tmp -> /private/tmp.
                
                try Utility.makeDirectories(root.appending("foo").asString)
                try Utility.makeDirectories(root.appending("bar/baz/goo").asString)
                try symlink(create: root.appending("foo/symlink").asString, pointingAt: root.appending("bar").asString, relativeTo: root.asString)
                
                XCTAssertTrue(root.appending("foo/symlink").asString.isSymlink)
                XCTAssertEqual(try! realpath(root.appending("foo/symlink").asString), root.appending("bar").asString)
                XCTAssertTrue(try! realpath(root.appending("foo/symlink/baz").asString).isDirectory)

                try Utility.removeFileTree(root.appending("foo").asString)

                XCTAssertFalse(root.appending("foo").asString.exists)
                XCTAssertFalse(root.appending("foo").asString.isDirectory)
                XCTAssertTrue(root.appending("bar/baz").asString.isDirectory)
                XCTAssertTrue(root.appending("bar/baz/goo").asString.isDirectory)
            }
        } catch {
            print(error)
            XCTFail()
        }
    }

    static var allTests = [
        ("testDoesNotFollowSymlinks", testDoesNotFollowSymlinks),
    ]
}
