/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class DeltaAlgorithmTests: XCTestCase {

    func testBasics() {
        let da = DeltaAlgorithm<Int>()

        do {
            // [0, 20) should minimize to {3,5,7}
            let failureSet: Set = [3, 5, 7]
            let result = da.run(changes: Set(0..<20)) {
                // If changes includes failure set.
                $0.union(failureSet) == $0
            }
            XCTAssertEqual(result, failureSet)
        }

        do {
            let failureSet: Set = [3, 5, 7]
            // [10, 20) should minimize to [10,20)
            let result = da.run(changes: Set(10..<20)) {
                $0.union(failureSet) == $0
            }
            XCTAssertEqual(result, Set(10..<20))
        }

        do {
            let failureSet = Set(0..<10)
            // [0, 4) should minimize to [0,4) in 11 tests.
            let result = da.run(changes: Set(0..<4)) {
                $0.union(failureSet) == $0
            }
            XCTAssertEqual(result, Set(0..<4))
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
