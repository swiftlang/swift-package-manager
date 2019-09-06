/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCTestSupport

private enum DummyError: Swift.Error {
    case somethingWentWrong
}

private enum OtherDummyError: Swift.Error {
    case somethingElseWentWrong
    case andYetAnotherThingToGoWrong
}

class ResultTests: XCTestCase {

    func testAnyError() {
        func doSomething(right: Bool) -> Result<String, AnyError> {
            if right {
                return .success("All OK.")
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
            XCTAssertEqual(error.underlyingError as? DummyError, DummyError.somethingWentWrong)
        }

        do {
            // Create an any error and check it doesn't nest.
            let error = AnyError(DummyError.somethingWentWrong)
            XCTAssertEqual(error.underlyingError as? DummyError, DummyError.somethingWentWrong)
            let nested = AnyError(error)
            XCTAssertEqual(nested.underlyingError as? DummyError, DummyError.somethingWentWrong)

            // Check can create result directly from error.
            let result: Result<String, AnyError> = Result(DummyError.somethingWentWrong)
            if case let .failure(resultError) = result {
                XCTAssertEqual(resultError.underlyingError as? DummyError, DummyError.somethingWentWrong)
            } else {
                XCTFail("Wrong result value \(result)")
            }
        }

        do {
            // Check any error closure initializer.
            func throwing() throws -> String {
                throw DummyError.somethingWentWrong
            }
            let result = Result(anyError: { try throwing() })
            if case let .failure(resultError) = result {
                XCTAssertEqual(resultError.underlyingError as? DummyError, DummyError.somethingWentWrong)
            } else {
                XCTFail("Wrong result value \(result)")
            }
        }
    }

    func testMapAny() throws {
        func throwing(_ shouldThrow: Bool) throws -> String {
            if shouldThrow {
                throw DummyError.somethingWentWrong
            }
            return " World"
        }

        // We should be able to map when we have value in result and our closure doesn't throw.
        let success = Result<String, AnyError>.success("Hello").mapAny { value -> String in
            let second = try throwing(false)
            return value + second
        }
        XCTAssertEqual(try success.get(), "Hello World")

        // We don't have a value, closure shouldn't matter.
        let failure1 = Result<String, AnyError>(DummyError.somethingWentWrong).mapAny { value -> String in
            let second = try throwing(false)
            return value + second
        }
        XCTAssertThrowsAny(DummyError.somethingWentWrong) {
            _ = try failure1.get()
        }

        // We have a value, but our closure throws.
        let failure2 = Result<String, AnyError>.success("Hello").mapAny { value -> String in
            let second = try throwing(true)
            return value + second
        }
        XCTAssertThrowsAny(DummyError.somethingWentWrong) {
            _ = try failure2.get()
        }
    }
}

public func XCTAssertThrowsAny<T: Swift.Error>(_ expectedError: T, file: StaticString = #file, line: UInt = #line, _ body: () throws -> ()) where T: Equatable {
    do {
        try body()
        XCTFail("body completed successfully", file: file, line: line)
    } catch let error as AnyError {
        XCTAssertEqual(error.underlyingError as? T, expectedError, file: file, line: line)
    } catch {
        XCTFail("unexpected error thrown", file: file, line: line)
    }
}
