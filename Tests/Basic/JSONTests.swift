/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

@testable import Basic

class JSONTests: XCTestCase {
    func testEncoding() {
        // Test the basics of encoding each object type.
        func encode(_ item: JSON) -> String {
            return item.toBytes().asString ?? "<unrepresentable>"
        }

        XCTAssertEqual(encode(.bool(false)), "false")
        XCTAssertEqual(encode(.int(1)), "1")
        XCTAssertEqual(encode(.string("hi")), "\"hi\"")
        XCTAssertEqual(encode(.array([1, "hi"])), "[1, \"hi\"]")
        XCTAssertEqual(encode(.dictionary(["a": 1, "b": "hi"])), "{\"a\": 1, \"b\": \"hi\"}")
    }
}

extension JSONTests {
    static var allTests: [(String, (JSONTests) -> () throws -> Void)] {
        return [
            ("testEncoding", testEncoding),
        ]
    }
}
