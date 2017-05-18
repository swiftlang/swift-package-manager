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

    private let startSequence = (0..<(magnitude*2)).map(prng)
    private let overlappingSequence = ((magnitude*1)..<(magnitude*3)).map(prng)

    private var arr: SortedArray<Int> = .init(areInIncreasingOrder: <)

    override func setUp() {
        arr = .init(areInIncreasingOrder: <)
        arr.insert(contentsOf: startSequence)
    }

    func testPerformanceOfSortedArrayInAscendingOrder() {
        
        measure() {
            for i in 1...1000 {
                self.arr.insert(i)
            }
        }
    }

    func testPerformanceOfSortedArrayInsertWithDuplicates() {
        measure() {
            for element in self.overlappingSequence {
                self.arr.insert(element)
            }
        }
    }

    func testPerformanceOfSortedArrayInsertContentsOfWithDuplicates() {
        measure() {
            self.arr.insert(contentsOf: self.overlappingSequence)
        }
    }
}
