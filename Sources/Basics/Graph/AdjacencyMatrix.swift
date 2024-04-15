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

/// A matrix storing bits of `true`/`false` state for a given combination of row and column indices. Used as
/// a square matrix indicating edges in graphs, where rows and columns are indices in a storage of graph's nodes.
///
/// For example, in a graph that contains 3 nodes `matrix[row: 1, column: 2]` evaluating to `true` means an edge
/// between nodes with indices `1` and `2` exists. `matrix[row: 1, column: 2]` evaluating to `false` means that no
/// edge exists.
///
/// See https://en.wikipedia.org/wiki/Adjacency_matrix for more details.
struct AdjacencyMatrix {
    let columns: Int
    let rows: Int
    private var bytes: [UInt8]

    /// Allocates a new bit matrix with a given size.
    /// - Parameters:
    ///   - rows: Number of rows in the matrix.
    ///   - columns: Number of columns in the matrix.
    init(rows: Int, columns: Int) {
        self.columns = columns
        self.rows = rows
        
        let (quotient, remainder) = (rows * columns).quotientAndRemainder(dividingBy: 8)
        self.bytes = .init(repeating: 0, count: quotient + (remainder > 0 ? 1 : 0))
    }

    var bitCount: Int {
        bytes.count * 8
    }

    private func calculateOffsets(row: Int, column: Int) -> (byteOffset: Int, bitOffsetInByte: Int) {
        let totalBitOffset = row * columns + column
        return (byteOffset: totalBitOffset / 8, bitOffsetInByte: totalBitOffset % 8)
    }

    subscript(row: Int, column: Int) -> Bool {
        get {
            let (byteOffset, bitOffsetInByte) = calculateOffsets(row: row, column: column)

            let result = (self.bytes[byteOffset] >> bitOffsetInByte) & 1
            return result == 1
        }

        set {
            let (byteOffset, bitOffsetInByte) = calculateOffsets(row: row, column: column)

            self.bytes[byteOffset] |= 1 << bitOffsetInByte
        }
    }
}
