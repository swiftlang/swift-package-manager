/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class CollectionAlgorithmsTests: XCTestCase {
    func testRIndex() {
        var str = "hello"
        XCTAssertEqual(str.characters.rindex(of: "h"), str.startIndex)
        XCTAssertEqual(str.characters.rindex(of: "h", from: str.index(after: str.startIndex)), nil)
        XCTAssertEqual(str.characters.rindex(of: "o"), str.characters.index(of: "o"))
        XCTAssertEqual(str.characters.rindex(of: "l"), str.index(after: str.characters.index(where: { $0 == "l" })!))
        XCTAssertEqual(str.characters.rindex(of: "x"), nil)
    }

    func testFindDuplicates() {
        XCTAssertEqual([1, 2, 3, 2, 1].findDuplicates(), [2, 1])
        XCTAssertEqual(["foo", "bar"].findDuplicates(), [])
        XCTAssertEqual(["foo", "Foo"].findDuplicates(), [])
    }

    static var allTests = [
        ("testRIndex", testRIndex),
        ("testFindDuplicates", testFindDuplicates),
    ]
}
