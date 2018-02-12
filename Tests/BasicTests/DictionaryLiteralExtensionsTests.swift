/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Basic

class DictionaryLiteralExtensionsTests: XCTestCase {

    func testDescription() {
        XCTAssertEqual(DictionaryLiteral(dictionaryLiteral: ("foo", 1)).description, "[foo: 1]")
        XCTAssertEqual(DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)).description, "[foo: 1, bar: 2]")
    }

    func testEquality() {
        XCTAssertTrue(DictionaryLiteral(dictionaryLiteral: ("foo", 1)) == DictionaryLiteral(dictionaryLiteral: ("foo", 1)))
        XCTAssertTrue(DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)) == DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)))

        XCTAssertFalse(DictionaryLiteral(dictionaryLiteral: ("no-foo", 1), ("bar", 2)) == DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)))
        XCTAssertFalse(DictionaryLiteral(dictionaryLiteral: ("foo", 0), ("bar", 2)) == DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)))
        XCTAssertFalse(DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2), ("hoge", 3)) == DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)))
        XCTAssertFalse(DictionaryLiteral(dictionaryLiteral: ("foo", 1), ("bar", 2)) == DictionaryLiteral(dictionaryLiteral: ("bar", 2), ("foo", 1)))
    }

    static var allTests = [
        ("testDescription", testDescription),
        ("testEquality", testEquality),
    ]
}
