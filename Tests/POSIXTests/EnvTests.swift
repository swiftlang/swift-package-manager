/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import POSIX
import TestSupport

class EnvTests: XCTestCase {
    enum CustomEnvError: Swift.Error {
        case someError
    }

    func getenv(_ variable: String) -> String? {
        return ProcessInfo.processInfo.environment[variable]
    }

    func testSet() throws {
        let key = "XCTEST_TEST"
        let value = "TEST"
        XCTAssertNil(getenv(key))
        try POSIX.setenv(key, value: value)
        XCTAssertEqual(value, getenv(key))
        try POSIX.unsetenv(key)
        XCTAssertNil(getenv(key))
    }

    func testWithCustomEnv() throws {
        let key = "XCTEST_TEST"
        let value = "TEST"
        XCTAssertNil(getenv(key))
        try withCustomEnv([key: value]) {
            XCTAssertEqual(value, getenv(key))
        }
        XCTAssertNil(getenv(key))
        do {
            try withCustomEnv([key: value]) {
                XCTAssertEqual(value, getenv(key))
                throw CustomEnvError.someError
            }
        } catch CustomEnvError.someError {
        } catch {
            XCTFail("Incorrect error thrown")
        }
        XCTAssertNil(getenv(key))
    }
}
