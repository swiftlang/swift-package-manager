/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic

class DictionaryLiteralExtensionsTests: XCTestCase {

    func testDescription() {
        XCTAssertEqual(KeyValuePairs(dictionaryLiteral: ("foo", 1)).description, "[foo: 1]")
        XCTAssertEqual(KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)).description, "[foo: 1, bar: 2]")
    }

    func testEquality() {
        XCTAssertTrue(KeyValuePairs(dictionaryLiteral: ("foo", 1)) == KeyValuePairs(dictionaryLiteral: ("foo", 1)))
        XCTAssertTrue(KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)) == KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)))

        XCTAssertFalse(KeyValuePairs(dictionaryLiteral: ("no-foo", 1), ("bar", 2)) == KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)))
        XCTAssertFalse(KeyValuePairs(dictionaryLiteral: ("foo", 0), ("bar", 2)) == KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)))
        XCTAssertFalse(KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2), ("hoge", 3)) == KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)))
        XCTAssertFalse(KeyValuePairs(dictionaryLiteral: ("foo", 1), ("bar", 2)) == KeyValuePairs(dictionaryLiteral: ("bar", 2), ("foo", 1)))
    }
}
