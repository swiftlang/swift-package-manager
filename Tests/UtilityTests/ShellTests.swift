/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility

class ShellTests: XCTestCase {

    func testPopen() {
        XCTAssertEqual(try! popen(["echo", "foo"], environment: [:]), "foo\n")
    }

    func testPopenWithBinaryOutput() {
        if (try? popen(["cat", "/bin/cat"], environment: [:])) != nil {
            XCTFail("popen succeeded but should have faileds")
        }
    }

    static var allTests = [
        ("testPopen", testPopen),
        ("testPopenWithBinaryOutput", testPopenWithBinaryOutput)
    ]
}
