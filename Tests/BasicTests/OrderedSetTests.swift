/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

typealias OrderedSet = Basic.OrderedSet

class OrderedSetTests: XCTestCase {
    func testBasics() {
        // Create an empty set.
        var set = OrderedSet<String>()
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.contents, [])

        // Create a new set with some strings.
        set = OrderedSet(["one", "two", "three"])
        XCTAssertFalse(set.isEmpty)
        XCTAssertEqual(set.count, 3)
        XCTAssertEqual(set[0], "one")
        XCTAssertEqual(set[1], "two")
        XCTAssertEqual(set[2], "three")
        XCTAssertEqual(set.contents, ["one", "two", "three"])

        // Try adding the same item again - the set should be unchanged.
        XCTAssertEqual(set.append("two"), false)
        XCTAssertEqual(set.count, 3)
        XCTAssertEqual(set[0], "one")
        XCTAssertEqual(set[1], "two")
        XCTAssertEqual(set[2], "three")

        // Remove the last element.
        let three = set.removeLast()
        XCTAssertEqual(set.count, 2)
        XCTAssertEqual(set[0], "one")
        XCTAssertEqual(set[1], "two")
        XCTAssertEqual(three, "three")

        // Remove all the objects.
        set.removeAll(keepingCapacity: true)
        XCTAssertEqual(set.count, 0)
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.contents, [])
    }

    func testMutation() {
        var set = OrderedSet<Int>()
        set.append(1)
        set.append(2)
        set.append(3)
        XCTAssertEqual(set.contents, [1, 2, 3])

        set[0] = 4
        XCTAssertEqual(set.contents, [4, 2, 3])
        XCTAssertFalse(set.contains(1))
        XCTAssert(set.contains(4))

        set[2] = 9
        XCTAssertEqual(set.contents, [4, 2, 9])
        XCTAssertFalse(set.contains(3))
        XCTAssert(set.contains(9))

        XCTAssertEqual(set[0..<2], [4, 2])
        set[0..<2] = [6, 7]
        XCTAssertEqual(set, [6, 7, 9])
        XCTAssertFalse(set.contains(4))
        XCTAssert(set.contains(6))
        XCTAssertFalse(set.contains(2))
        XCTAssert(set.contains(7))
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testMutation", testMutation),
    ]
}
