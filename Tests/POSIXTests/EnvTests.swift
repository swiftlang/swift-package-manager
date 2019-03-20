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

    func testGet() throws {
        XCTAssertNotNil(ProcessInfo.environment["PATH"])
    }

    func testSet() throws {
        let key = "XCTEST_TEST"
        let value = "TEST"
        XCTAssertNil(ProcessInfo.environment[key])
        try POSIX.setenv(key, value: value)
        XCTAssertEqual(value, ProcessInfo.environment[key])
        try POSIX.unsetenv(key)
        XCTAssertNil(ProcessInfo.environment[key])
    }

    func testWithCustomEnv() throws {
        let key = "XCTEST_TEST"
        let value = "TEST"
        XCTAssertNil(ProcessInfo.environment[key])
        try withCustomEnv([key: value]) {
            XCTAssertEqual(value, ProcessInfo.environment[key])
        }
        XCTAssertNil(ProcessInfo.environment[key])
        do {
            try withCustomEnv([key: value]) {
                XCTAssertEqual(value, ProcessInfo.environment[key])
                throw CustomEnvError.someError
            }
        } catch CustomEnvError.someError {
        } catch {
            XCTFail("Incorrect error thrown")
        }
        XCTAssertNil(ProcessInfo.environment[key])
    }
}
