/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport

class TestSupportTests: XCTestCase {
    func testAssertMatchStringLists() {
        XCTAssertMatch([], [])
        XCTAssertMatch(["a"], [])

        XCTAssertMatch([], [.anySequence])
        XCTAssertMatch(["a"], [.anySequence])
        XCTAssertMatch(["a", "b"], [.anySequence])

        XCTAssertMatch([], [.start])
        XCTAssertMatch([], [.start, .end])
        XCTAssertMatch([], [.end])
        XCTAssertNoMatch([], [.end, "a"])

        XCTAssertMatch(["a"], [.start, "a", .end])
        XCTAssertMatch(["a"], [.start, .anySequence, .end])
        XCTAssertNoMatch(["a"], [.start, "b", .end])
        XCTAssertNoMatch(["a"], ["a", .start])

        XCTAssertMatch(["a", "c"], ["a", .anySequence, "c"])
        XCTAssertMatch(["a", "b", "c"], ["a", .anySequence, "c"])
        XCTAssertMatch(["a", "b", "b", "c"], ["a", .anySequence, "c"])
    }

    static var allTests = [
        ("testAssertMatchStringLists", testAssertMatchStringLists),
    ]
}
