/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import sys
import XCTest

class ShellTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("test_popen", testPopen),
            ("testPopenWithBufferLargerThanThatAllocated", testPopenWithBufferLargerThanThatAllocated)
        ]
    }

    func testPopen() {
        XCTAssertEqual(try! popen(["echo", "foo"]), "foo\n")
    }

    func testPopenWithBufferLargerThanThatAllocated() {
        let path = Path.join(__FILE__, "../../dep/FunctionalBuildTests.swift").normpath
        XCTAssertGreaterThan(try! popen(["cat", path]).characters.count, 4096)
    }
}
