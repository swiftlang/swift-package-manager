/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class JSONTests: XCTestCase {
    func testEncoding() {
        // Test the basics of encoding each object type.
        func encode(_ item: JSON) -> String {
            return item.toBytes().asString ?? "<unrepresentable>"
        }

        XCTAssertEqual(encode(.null), "null")
        XCTAssertEqual(encode(.bool(false)), "false")
        XCTAssertEqual(encode(.int(1)), "1")
        XCTAssertEqual(encode(.string("hi")), "\"hi\"")
        XCTAssertEqual(encode(.array([.int(1), .string("hi")])), "[1, \"hi\"]")
        XCTAssertEqual(encode(.dictionary(["a": .int(1), "b": .string("hi")])), "{\"a\": 1, \"b\": \"hi\"}")
    }
    
    func testDecoding() {
        // Test the basics of encoding each object type.
        func decode(_ string: String) -> JSON? {
            return try? JSON(bytes: ByteString(string))
        }

        XCTAssertEqual(decode(""), nil)
        XCTAssertEqual(decode("this is not json"), nil)
        XCTAssertEqual(decode("null"), .null)
        XCTAssertEqual(decode("false"), .bool(false))
        XCTAssertEqual(decode("true"), .bool(true))
        XCTAssertEqual(decode("1"), .int(1))
        XCTAssertEqual(decode("1.2"), .double(1.2))
        XCTAssertEqual(decode("\"hi\""), .string("hi"))
        XCTAssertEqual(decode("[null, \"hi\"]"), .array([.null, .string("hi")]))
        XCTAssertEqual(decode("{\"a\": null, \"b\": \"hi\"}"), .dictionary(["a": .null, "b": .string("hi")]))
    }
}

extension JSONTests {
    static var allTests: [(String, (JSONTests) -> () throws -> Void)] {
        return [
            ("testEncoding", testEncoding),
            ("testDecoding", testDecoding),
        ]
    }
}
