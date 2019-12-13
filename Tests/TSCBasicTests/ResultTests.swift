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

private enum DummyError: Error, Equatable {
    case somethingWentWrong
}

private enum OtherDummyError: Error, Equatable {
    case somethingElseWentWrong
    case andYetAnotherThingToGoWrong
}

class ResultTests: XCTestCase {
    func testTryMap() {
        let result1 = Result<Int, Error>.success(1).tryMap({ $0 + 1 })
        XCTAssertEqual(result1.success, 2)

        let result2 = Result<Int, Error>.failure(DummyError.somethingWentWrong).tryMap({ (value: Int) -> Int in
            XCTFail("should not reach here")
            return value
        })
        XCTAssertEqual(result2.failure as? DummyError, DummyError.somethingWentWrong)

        let result3 = Result<Int, Error>.success(1).tryMap({ (value: Int) -> Int in
            throw OtherDummyError.somethingElseWentWrong
        })
        XCTAssertEqual(result3.failure as? OtherDummyError, OtherDummyError.somethingElseWentWrong)

        let result4 = Result<Int, Error>.failure(DummyError.somethingWentWrong).tryMap({ (value: Int) -> Int in
            XCTFail("should not reach here")
            throw OtherDummyError.somethingElseWentWrong
        })
        XCTAssertEqual(result4.failure as? DummyError, DummyError.somethingWentWrong)
    }
}

extension Result {
    var success: Success? {
        switch self {
        case .success(let success):
            return success
        case .failure:
            return nil
        }
    }

    var failure: Failure? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}
