/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

private enum DummyError: Swift.Error {
    case somethingWentWrong
}

class ResultTests: XCTestCase {

    func testBasics() throws {

        func doSomething(right: Bool) -> Result<String, DummyError> {
            if right {
                return Result("All OK.")
            }
            return Result(DummyError.somethingWentWrong)
        }
        // Success.
        switch doSomething(right: true) {
        case .success(let string):
            XCTAssertEqual(string, "All OK.")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        // Error.
        switch doSomething(right: false) {
        case .success(let string):
            XCTFail("Unexpected success: \(string)")
        case .failure(let error):
            XCTAssertEqual(error, DummyError.somethingWentWrong)
        }

        // Test dematerialize.
        XCTAssertEqual(try doSomething(right: true).dematerialize(), "All OK.")
        do {
            _ = try doSomething(right: false).dematerialize()
            XCTFail("Unexpected success")
        } catch DummyError.somethingWentWrong {}

        func should(`throw`: Bool) throws -> Int {
            if `throw` {
                throw DummyError.somethingWentWrong
            }
            return 1
        }

        // Test closure.
        let result: Result<Int, DummyError> = try Result {
            return try should(throw: false)
        }
        XCTAssertEqual(try result.dematerialize(), 1)
    }

    func testAnyError() {
        func doSomething(right: Bool) -> Result<String, AnyError> {
            if right {
                return Result("All OK.")
            }
            return Result(AnyError(DummyError.somethingWentWrong))
        }

        // Success.
        switch doSomething(right: true) {
        case .success(let string):
            XCTAssertEqual(string, "All OK.")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        // Error.
        switch doSomething(right: false) {
        case .success(let string):
            XCTFail("Unexpected success: \(string)")
        case .failure(let error):
            XCTAssertEqual(error.underlyingError as? DummyError, DummyError.somethingWentWrong)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testAnyError", testAnyError),
    ]
}
