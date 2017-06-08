/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import Basic

class CStringArrayTests: XCTestCase {
    func testInitialization() {
        let array = CStringArray(["hello", "world"])
        XCTAssertEqual(array.cArray.count, 3)
        XCTAssertEqual(String(cString: array.cArray[0]!), "hello")
        XCTAssertEqual(String(cString: array.cArray[1]!), "world")
        XCTAssertNil(array.cArray[2])
    }

    static var allTests = [
        ("testInitialization",  testInitialization),
    ]
}
