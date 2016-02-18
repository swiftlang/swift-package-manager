/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Build
import XCTest

final class DescribeTests: XCTestCase {
    func testDescribingNoModulesThrows() {
        do {
            let _ = try describe("foo", .Debug, [], [], Xcc: [], Xld: [], Xswiftc: [])
            XCTFail("This call should throw")
        } catch Build.Error.NoModules {
            XCTAssert(true, "This error should be throw")
        } catch {
            XCTFail("No other error should be thrown")
        }
    }
}

extension DescribeTests {
    static var allTests: [(String, DescribeTests -> () throws -> Void)] {
        return [
            ("testDescribingNoModulesThrows", testDescribingNoModulesThrows),
        ]
    }
}
