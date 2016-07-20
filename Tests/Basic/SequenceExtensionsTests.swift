/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class SequenceExtensionsTests: XCTestCase {
    func testNestedIterator() {
        XCTAssertEqual(Array([[Int]()].makeNestedIterator{ $0 }), [])
        XCTAssertEqual(Array([[1]].makeNestedIterator{ $0 }), [1])
        XCTAssertEqual(Array([[1,2],[],[3],[4,5],[]].makeNestedIterator{ $0 }), [1,2,3,4,5])

        struct S {
            let elements = [1, 2]
        }
        XCTAssertEqual(Array([S(), S()].makeNestedIterator{ $0.elements }), [1,2,1,2])
    }

    static var allTests = [
        ("testNestedIterator", testNestedIterator),
    ]
}
