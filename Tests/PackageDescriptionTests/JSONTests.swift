/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import PackageDescription

class JSONTests: XCTestCase {
    func testEncoding() {
        // Test the basics of encoding each object type.
        func encode(_ item: JSON) -> String {
            return item.toString()
        }

        XCTAssertEqual(encode(.null), "null")
        XCTAssertEqual(encode(.bool(false)), "false")
        XCTAssertEqual(encode(.int(1)), "1")
        XCTAssertEqual(encode(.string("hi")), "\"hi\"")
        XCTAssertEqual(encode(.array([.int(1), .string("hi")])), "[1, \"hi\"]")
        XCTAssertEqual(encode(.dictionary(["a": .int(1), "b": .string("hi")])), "{\"a\": 1, \"b\": \"hi\"}")
    }

    static var allTests = [
        ("testEncoding", testEncoding),
    ]
}
