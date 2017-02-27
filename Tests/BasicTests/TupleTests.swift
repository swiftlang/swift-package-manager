/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class TupleTests: XCTestCase {

    func testBasics() throws {
        XCTAssertTrue([("A", "A")] == [("A", "A")])
        XCTAssertFalse([("A", "A")] == [("A", "B")])

        XCTAssertTrue([("A", 1)] == [("A", 1)])
        XCTAssertFalse([("A", 1)] == [("A", 2)])
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
