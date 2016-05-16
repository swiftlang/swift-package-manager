/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageType
import XCTest

class c99nameTests: XCTestCase {
    func testSimpleName() {
        let name = assertc99Name("foo")
        XCTAssertEqual(name, "foo")
    }

    func testNameWithInvalidCharacter() {
        let name = assertc99Name("foo-bar")
        XCTAssertEqual(name, "foo_bar")
    }

    func testNameWithLeadingInvalidChar() {
        let name = assertc99Name("1foo-bar12")
        XCTAssertEqual(name, "_foo_bar12")
    }
}

func assertc99Name(_ name: String) -> String {
    do {
        return try c99name(name: name)
    } catch {
        XCTFail("Couldn't find the c99name: \(error)")
        fatalError()
    }
}
