//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import XCTest

final class AdjacencyMatrixTests: XCTestCase {
    func testEmpty() {
        var matrix = AdjacencyMatrix(rows: 0, columns: 0)
        XCTAssertEqual(matrix.bitCount, 0)

        matrix = AdjacencyMatrix(rows: 0, columns: 42)
        XCTAssertEqual(matrix.bitCount, 0)

        matrix = AdjacencyMatrix(rows: 42, columns: 0)
        XCTAssertEqual(matrix.bitCount, 0)
    }

    func testBits() {
        for count in 1..<10 {
            var matrix = AdjacencyMatrix(rows: count, columns: count)
            for row in 0..<count {
                for column in 0..<count {
                    XCTAssertFalse(matrix[row, column])
                    matrix[row, column] = true
                    XCTAssertTrue(matrix[row, column])
                }
            }
        }
    }
}
