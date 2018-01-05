/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class EditDistanceTests: XCTestCase {

    func testBasics() {
        XCTAssertEqual(editDistance("Foo", "Fo"), 1)
        XCTAssertEqual(editDistance("Foo", "Foo"), 0)
        XCTAssertEqual(editDistance("Bar", "Foo"), 3)
        XCTAssertEqual(editDistance("ABCDE", "ABDE"), 1)
        XCTAssertEqual(editDistance("sunday", "saturday"), 3)
        XCTAssertEqual(editDistance("FOO", "foo"), 3)
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
