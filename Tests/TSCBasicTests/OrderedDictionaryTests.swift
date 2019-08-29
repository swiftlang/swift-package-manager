/*
 This source file is part of the Swift.org open source project

 Copyright 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic

class OrderedDictionaryTests: XCTestCase {
    func testBasics() {
        var dict: OrderedDictionary = ["a": "aa", "b": "bb", "c": "cc", "d": "dd"]
        XCTAssertEqual(dict.description, "[a: aa, b: bb, c: cc, d: dd]")

        dict["a"] = "aaa"
        XCTAssertEqual(dict.description, "[a: aaa, b: bb, c: cc, d: dd]")

        dict["e"] = "ee"
        XCTAssertEqual(dict.description, "[a: aaa, b: bb, c: cc, d: dd, e: ee]")

        dict["b"] = nil
        XCTAssertEqual(dict.description, "[a: aaa, c: cc, d: dd, e: ee]")
    }
}
