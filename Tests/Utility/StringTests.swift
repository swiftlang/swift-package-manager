/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Utility
import XCTest

class StringTests: XCTestCase {

    func testTrailingChomp() {
        XCTAssertEqual("abc\n".chomp(), "abc")
        XCTAssertEqual("abc\r\n".chomp(), "abc")
        XCTAssertEqual("abc\r\n\r\n".chomp(), "abc")
        XCTAssertEqual("abc\r\n\r\r\n".chomp(), "abc\r\n\r")
        XCTAssertEqual("abc\n \n".chomp(), "abc\n ")
    }
    
    func testSeparatorChomp() {
        XCTAssertEqual("abc".chomp("c"), "ab")
        XCTAssertEqual("abc\n".chomp("c"), "abc\n")
        XCTAssertEqual("abc\n c".chomp("c"), "abc\n ")
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


class URLTests: XCTestCase {

    func testSchema() {
        let a = "http://github.com/foo/bar"
        let b = "https://github.com/foo/bar"
        let c = "git@github.com/foo/bar"
        XCTAssertEqual(Utility.URL.scheme(a), "http")
        XCTAssertEqual(Utility.URL.scheme(b), "https")
        XCTAssertEqual(Utility.URL.scheme(c), "git")
    }
}
