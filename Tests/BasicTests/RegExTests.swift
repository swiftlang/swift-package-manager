/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import Basic

class RegExTests: XCTestCase {
    
    func testErrors() {
        // https://bugs.swift.org/browse/SR-5557
      #if os(macOS)
        XCTAssertThrowsError(try RegEx(pattern: "("))
      #endif
    }
    
    func testMatchGroups() throws {
        try XCTAssert(RegEx(pattern: "([a-z]+)([0-9]+)").matchGroups(in: "foo1 bar2 baz3") == [["foo", "1"], ["bar", "2"], ["baz", "3"]])
        try XCTAssert(RegEx(pattern: "[0-9]+").matchGroups(in: "foo bar baz") == [])
        try XCTAssert(RegEx(pattern: "[0-9]+").matchGroups(in: "1") == [[]])
    }

    static var allTests = [
        ("testErrors", testErrors),
        ("testMatchGroups", testMatchGroups),
    ]
}
