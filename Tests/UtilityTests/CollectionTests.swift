/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Utility
import XCTest

class CollectionTests: XCTestCase {
    
    func testSplitAround() {
        
        func eq(_ lhs: ([Character], [Character]?), _ rhs: ([Character], [Character]?), file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(lhs.0, rhs.0, file: file, line: line)
            XCTAssertEqual(lhs.1 ?? [], rhs.1 ?? [], file: file, line: line)
        }
        
        eq([].split(around: [":"]), ([], nil))
        eq(["f", "o", "o"].split(around: [":"]), (["f", "o", "o"], nil))
        eq(["f", "o", "o", ":"].split(around: [":"]), (["f", "o", "o"], []))
        eq([":", "b", "a", "r"].split(around: [":"]), ([], ["b", "a", "r"]))
        eq(["f", "o", "o", ":", "b", "a", "r"].split(around: [":"]), (["f", "o", "o"], ["b", "a", "r"]))
    }

    func testSplitisMatching() {
        do {
            let array = [false, true, true, false, false]
            let result = array.split({ $0 == true })
            XCTAssertEqual(result.0, [true, true])
            XCTAssertEqual(result.1, [false, false, false])
        }

        do {
            let array = [0, 1, 1, 2, 0, 0, 0]
            let result = array.split({ $0 == 0 })
            XCTAssertEqual(result.0, [0, 0, 0, 0])
            XCTAssertEqual(result.1, [1, 1, 2])
        }

        do {
            let array = [1, 1, 2]
            let result = array.split({ $0 == 0 })
            XCTAssertEqual(result.0, [])
            XCTAssertEqual(result.1, [1, 1, 2])
        }

        do {
            let array = [Int]()
            let result = array.split({ $0 == 0 })
            XCTAssertEqual(result.0, [])
            XCTAssertEqual(result.1, [])
        }
    }

    static var allTests = [
        ("testSplitAround", testSplitAround),
        ("testSplitisMatching", testSplitisMatching),
    ]
}

