/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic

class StringConversionTests: XCTestCase {

    func testShellEscaped() {

        var str = "hello-_123"
        XCTAssertEqual("hello-_123", str.spm_shellEscaped())

        str = "hello world"
        XCTAssertEqual("'hello world'", str.spm_shellEscaped())

        str = "hello 'world"
        str.spm_shellEscape()
        XCTAssertEqual("'hello '\\''world'", str)

        str = "hello world swift"
        XCTAssertEqual("'hello world swift'", str.spm_shellEscaped())

        str = "hello?world"
        XCTAssertEqual("'hello?world'", str.spm_shellEscaped())

        str = "hello\nworld"
        XCTAssertEqual("'hello\nworld'", str.spm_shellEscaped())

        str = "hello\nA\"B C>D*[$;()^><"
        XCTAssertEqual("'hello\nA\"B C>D*[$;()^><'", str.spm_shellEscaped())
    }

    func testLocalizedJoin() {
        XCTAssertEqual("foo", ["foo"].spm_localizedJoin(type: .conjunction))
        XCTAssertEqual("foo", ["foo"].spm_localizedJoin(type: .disjunction))

        XCTAssertEqual("foo or bar", ["foo", "bar"].spm_localizedJoin(type: .disjunction))
        XCTAssertEqual("foo, bar, and baz", ["foo", "bar", "baz"].spm_localizedJoin(type: .conjunction))
    }
}
