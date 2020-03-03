/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCUtility
import XCTest

class StringTests: XCTestCase {
    func testTrailingChomp() {
        XCTAssertEqual("abc\n".spm_chomp(), "abc")
        XCTAssertEqual("abc\r\n".spm_chomp(), "abc")
        XCTAssertEqual("abc\r\n\r\n".spm_chomp(), "abc")
        XCTAssertEqual("abc\r\n\r\r\n".spm_chomp(), "abc\r\n\r")
        XCTAssertEqual("abc\n \n".spm_chomp(), "abc\n ")
    }

    func testSeparatorChomp() {
        XCTAssertEqual("abc".spm_chomp(separator: "c"), "ab")
        XCTAssertEqual("abc\n".spm_chomp(separator: "c"), "abc\n")
        XCTAssertEqual("abc\n c".spm_chomp(separator: "c"), "abc\n ")
    }

    func testEmptyChomp() {
        XCTAssertEqual("".spm_chomp(), "")
        XCTAssertEqual(" ".spm_chomp(), " ")
        XCTAssertEqual("\n\n".spm_chomp(), "")
    }

    func testChuzzle() {
        XCTAssertNil("".spm_chuzzle())
        XCTAssertNil(" ".spm_chuzzle())
        XCTAssertNil(" \t ".spm_chuzzle())
        XCTAssertNil(" \t\n".spm_chuzzle())
        XCTAssertNil(" \t\r\n".spm_chuzzle())
        XCTAssertEqual(" a\t\r\n".spm_chuzzle(), "a")
        XCTAssertEqual("b".spm_chuzzle(), "b")
    }

    func testSplitAround() {
        func eq(_ lhs: (String, String?), _ rhs: (String, String?), file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(lhs.0, rhs.0, file: file, line: line)
            XCTAssertEqual(lhs.1, rhs.1, file: file, line: line)
        }

        eq("".spm_split(around: "::"), ("", nil))
        eq("foo".spm_split(around: "::"), ("foo", nil))
        eq("foo::".spm_split(around: "::"), ("foo", ""))
        eq("::bar".spm_split(around: "::"), ("", "bar"))
        eq("foo::bar".spm_split(around: "::"), ("foo", "bar"))
    }
}

class URLTests: XCTestCase {
    func testSchema() {
        XCTAssertEqual(TSCUtility.URL.scheme("http://github.com/foo/bar"), "http")
        XCTAssertEqual(TSCUtility.URL.scheme("https://github.com/foo/bar"), "https")
        XCTAssertEqual(TSCUtility.URL.scheme("HTTPS://github.com/foo/bar"), "https")
        XCTAssertEqual(TSCUtility.URL.scheme("git@github.com/foo/bar"), "git")
        XCTAssertEqual(TSCUtility.URL.scheme("ssh@github.com/foo/bar"), "ssh")
        XCTAssertNil(TSCUtility.URL.scheme("github.com/foo/bar"))
        XCTAssertNil(TSCUtility.URL.scheme("user:/github.com/foo/bar"))
        XCTAssertNil(TSCUtility.URL.scheme("/path/to/something@2/hello"))
    }
}
