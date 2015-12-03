/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import sys

class StringTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testTrailingChomp", testTrailingChomp),
            ("testEmptyChomp", testEmptyChomp),
            ("testChuzzle", testChuzzle),
        ]
    }

    func testTrailingChomp() {
        XCTAssertEqual("abc\n".chomp(), "abc")
        XCTAssertEqual("abc\r\n".chomp(), "abc")
        XCTAssertEqual("abc\r\n\r\n".chomp(), "abc")
        XCTAssertEqual("abc\r\n\r\r\n".chomp(), "abc\r\n\r")
        XCTAssertEqual("abc\n \n".chomp(), "abc\n ")
    }

    func testEmptyChomp() {
        XCTAssertEqual("".chomp(), "")
        XCTAssertEqual(" ".chomp(), " ")
        XCTAssertEqual("\n\n".chomp(), "")
    }

    func testChuzzle() {
        XCTAssertNil("".chuzzle())
        XCTAssertNil(" ".chuzzle())
        XCTAssertNil(" \t ".chuzzle())
        XCTAssertNil(" \t\n".chuzzle())
        XCTAssertNil(" \t\r\n".chuzzle())
        XCTAssertEqual(" a\t\r\n".chuzzle(), "a")
        XCTAssertEqual("b".chuzzle(), "b")
    }
}


class URLTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testSchema", testSchema),
        ]
    }

    func testSchema() {
        let a = "http://github.com/foo/bar"
        let b = "https://github.com/foo/bar"
        let c = "git@github.com/foo/bar"
        XCTAssertEqual(sys.URL.scheme(a), "http")
        XCTAssertEqual(sys.URL.scheme(b), "https")
        XCTAssertEqual(sys.URL.scheme(c), "git")
    }
}
