/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TestSupport
import Basic

class SortedArrayPerfTests: XCTestCasePerf {
    func testPerformanceOfSortedArrayInAscendingOrder() {
        measure() {
            var arr = SortedArray<Int>(areInIncreasingOrder: <)
            for i in 1...200_000 {
                arr.insert(i)
            }
        }
    }

    func testPerformanceOfSortedArrayInsertWithDuplicates() {
        let initial = SortedArray<Int>(0..<80_000, areInIncreasingOrder: <)
        
        measure() {
            var arr = initial
            for element in 40_000..<120_000 {
                arr.insert(element)
            }
        }
    }

    func testPerformanceOfSortedArrayInsertContentsOfWithDuplicates() {
        let initial = SortedArray<Int>(0..<120_000, areInIncreasingOrder: <)
        
        measure() {
            var arr = initial
            arr.insert(contentsOf: 60_000..<180_000)
        }
    }

    func testPerformanceOfSmallSortedArrayInsertContentsOfWithDuplicates() {
        let initial = SortedArray<Int>(0..<100, areInIncreasingOrder: <)

        measure() {
            for _ in 1...2000 {
                var arr = initial
                arr.insert(contentsOf: 50..<150)
            }
        }
    }
}
