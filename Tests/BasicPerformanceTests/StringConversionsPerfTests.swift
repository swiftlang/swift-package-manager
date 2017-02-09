/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import TestSupport

class StringConversionsPerfTests: XCTestCasePerf {
    func testLongString() {
        let string = Array(0..<2000).map{ _ in "hello world"}.joined(separator: " ")
        measure {
            let N = 100
            var length = 0
            for _ in 0..<N {
                let shell = string.shellEscaped()
                length = length &+ shell.utf8.count
            }

            XCTAssertEqual(length, (string.utf8.count + 2) &* N)
        }
    }
}
