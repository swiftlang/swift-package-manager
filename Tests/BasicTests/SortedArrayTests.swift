/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class SortedArrayTests: XCTestCase {

    func testSortedArrayInAscendingOrder() throws {
        var arr = SortedArray<Int>(areInIncreasingOrder: <)
        arr.insert(15)
        arr.insert(14)
        arr.insert(100)
        arr.insert(-13)
        arr.insert(0)
        arr.insert(198)
        arr.insert(13)
        XCTAssertEqual(arr.values, [-13, 0, 13, 14, 15, 100, 198])

        arr.insert(contentsOf: [2, 1, 3, 0, 9])
        XCTAssertEqual(arr.values, [-13, 0, 0, 1, 2, 3, 9, 13, 14, 15, 100, 198])

        arr += [2, 3]
        XCTAssertEqual(arr.values, [-13, 0, 0, 1, 2, 2, 3, 3, 9, 13, 14, 15, 100, 198])
        
        arr.insert(-13)
        XCTAssertEqual(arr.values, [-13, -13, 0, 0, 1, 2, 2, 3, 3, 9, 13, 14, 15, 100, 198])
        
        arr.insert(198)
        XCTAssertEqual(arr.values, [-13, -13, 0, 0, 1, 2, 2, 3, 3, 9, 13, 14, 15, 100, 198, 198])
        
        arr.insert(contentsOf: [-15, -14])
        XCTAssertEqual(arr.values, [-15, -14, -13, -13, 0, 0, 1, 2, 2, 3, 3, 9, 13, 14, 15, 100, 198, 198])
    }
    
    func testSortedArrayInDescendingOrder() throws {
        var arr = SortedArray<Int>(areInIncreasingOrder: >)
        arr.insert(15)
        arr.insert(14)
        arr.insert(100)
        arr.insert(-13)
        arr.insert(0)
        arr.insert(198)
        arr.insert(13)
        XCTAssertEqual(arr.values, [198, 100, 15, 14, 13, 0, -13])
        
        arr.insert(contentsOf: [2, 1, 3, 0, 9])
        XCTAssertEqual(arr.values, [198, 100, 15, 14, 13, 9, 3, 2, 1, 0, 0, -13])
        
        arr += [2, 3]
        XCTAssertEqual(arr.values, [198, 100, 15, 14, 13, 9, 3, 3, 2, 2, 1, 0, 0, -13])
        
        arr.insert(-13)
        XCTAssertEqual(arr.values, [198, 100, 15, 14, 13, 9, 3, 3, 2, 2, 1, 0, 0, -13, -13])
        
        arr.insert(198)
        XCTAssertEqual(arr.values, [198, 198, 100, 15, 14, 13, 9, 3, 3, 2, 2, 1, 0, 0, -13, -13])
    }

    func testSortedArrayInsertIntoSmallerArray() throws {
        var arr = SortedArray<Int>(areInIncreasingOrder: <)
        arr.insert(contentsOf: [3])

        arr.insert(contentsOf: [1, 2])
        XCTAssertEqual(arr.values, [1, 2, 3])

        arr.insert(contentsOf: [4, 5, 6, 7])
        XCTAssertEqual(arr.values, [1, 2, 3, 4, 5, 6, 7])
    }

    func testSortedArrayInsertSlice() throws {
        let target = [0, 1, 2, 3, 4, 5, 6]
        var arr = SortedArray<Int>(areInIncreasingOrder: <)
        arr.insert(contentsOf: target[2...2])

        arr.insert(contentsOf: target[0...1])
        XCTAssertEqual(arr.values, [0, 1, 2])

        arr.insert(contentsOf: target[3...6])
        XCTAssertEqual(arr.values, target)
    }

    func testSortedArrayWithValues() throws {
        let arr = SortedArray<Int>([5, 4, 3, 2, 1], areInIncreasingOrder: <)
        XCTAssertEqual(arr.values, [1, 2, 3, 4, 5])
    }
    
    static var allTests = [
        ("testSortedArrayInAscendingOrder", testSortedArrayInAscendingOrder),
        ("testSortedArrayInDescendingOrder", testSortedArrayInDescendingOrder),
        ("testSortedArrayInsertIntoSmallerArray", testSortedArrayInsertIntoSmallerArray),
        ("testSortedArrayWithValues", testSortedArrayWithValues)
    ]
}
