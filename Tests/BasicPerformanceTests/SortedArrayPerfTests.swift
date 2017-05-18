/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TestSupport
import Basic

private let magnitude = 5000

private func prng(_ seed: Int) -> Int {
    return (seed &* 1299827) % magnitude
}

class SortedArrayPerfTests: XCTestCasePerf {

    private let firstSequence = (0..<(magnitude*2)).map(prng)
    private let secondSequence = ((magnitude*1)..<(magnitude*3)).map(prng)

    func testPerformanceOfSortedArrayInAscendingOrder() {
        
        measure() {
            var arr = SortedArray<Int>(areInIncreasingOrder: <)
            for i in 1...1000 {
                arr.insert(i)
            }
        }
    }

    func testPerformanceOfSortedArrayInsertWithDuplicates() {

        measure() {
            var arr = SortedArray<Int>(areInIncreasingOrder: <)
            for element in self.firstSequence {
                arr.insert(element)
            }
            for element in self.secondSequence {
                arr.insert(element)
            }
        }
    }

    func testPerformanceOfSortedArrayInsertContentsOfWithDuplicates() {

        measure() {
            var arr = SortedArray<Int>(areInIncreasingOrder: <)
            arr.insert(contentsOf: self.firstSequence)
            arr.insert(contentsOf: self.secondSequence)
        }
    }
}
