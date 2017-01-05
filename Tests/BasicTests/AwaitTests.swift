/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Dispatch

import Basic

class AwaitTests: XCTestCase {

    enum DummyError: Error {
        case error
    }

    func async(_ param: String, _ completion: @escaping (Result<String, AnyError>) -> Void) {
        DispatchQueue.global().async {
            completion(Result(param))
        }
    }

    func throwingAsync(_ param: String, _ completion: @escaping (Result<String, AnyError>) -> Void) {
        DispatchQueue.global().async {
            completion(Result(DummyError.error))
        }
    }

    func testBasics() throws {
        let value = try await { async("Hi", $0) }
        XCTAssertEqual("Hi", value)

        do {
            let value = try await { throwingAsync("Hi", $0) }
            XCTFail("Unexpected success \(value)")
        } catch let error as AnyError {
            XCTAssertEqual(error.underlyingError as? DummyError, DummyError.error)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
