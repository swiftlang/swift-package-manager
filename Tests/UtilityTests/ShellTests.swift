/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility

class ShellTests: XCTestCase {

    func testPopen() {
        XCTAssertEqual(try! popen(["echo", "foo"]), "foo\n")
    }

    func testPopenWithBufferLargerThanThatAllocated() {
        // FIXME: Disabled due to https://bugs.swift.org/browse/SR-2703
      #if false
        let path = AbsolutePath(#file).parentDirectory.parentDirectory.appending(components: "GetTests", "VersionGraphTests.swift")
        XCTAssertGreaterThan(try! popen(["cat", path.asString]).characters.count, 4096)
      #endif
    }

    func testPopenWithBinaryOutput() {
        // FIXME: Disabled due to https://bugs.swift.org/browse/SR-2703
      #if false
        if (try? popen(["cat", "/bin/cat"])) != nil {
            XCTFail("popen succeeded but should have faileds")
        }
      #endif
    }

    static var allTests = [
        ("testPopen", testPopen),
        ("testPopenWithBufferLargerThanThatAllocated", testPopenWithBufferLargerThanThatAllocated),
        ("testPopenWithBinaryOutput", testPopenWithBinaryOutput)
    ]
}
