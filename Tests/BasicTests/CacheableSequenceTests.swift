/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class CacheableSequenceTests: XCTestCase {
    func testBasics() throws {
        let s = sequence(first: 0, next: { i in
                return i < 5 ? i + 1 : nil
            })
        let s2 = CacheableSequence(s)
        XCTAssertEqual(Array(s2), Array(s2))
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
