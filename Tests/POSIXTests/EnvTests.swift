/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import POSIX

class EnvTests: XCTestCase {
    func testGet() throws {
        XCTAssertNotNil(POSIX.getenv("PATH"))
    }

    func testSet() throws {
        let key = "XCTEST_TEST"
        let value = "TEST"
        XCTAssertNil(POSIX.getenv(key))
        try POSIX.setenv(key, value: value)
        XCTAssertEqual(value, POSIX.getenv(key))
        try POSIX.unsetenv(key)
        XCTAssertNil(POSIX.getenv(key))
    }
}
