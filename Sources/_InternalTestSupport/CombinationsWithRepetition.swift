/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
package  struct CombinationsWithRepetition<C: Collection> : Sequence {

    let base: C
    let length: Int

    init(of base: C, length: Int) {
        self.base = base
        self.length = length
    }

    package struct Iterator : IteratorProtocol {
        let base: C

        var firstIteration = true
        var finished: Bool
        var positions: [C.Index]

        package init(of base: C, length: Int) {
            self.base = base
            finished = base.isEmpty
            positions = Array(repeating: base.startIndex, count: length)
        }

        package mutating func next() -> [C.Element]? {
            if firstIteration {
                firstIteration = false
            } else {
                // Update indices for next combination.
                finished = true
                for i in positions.indices.reversed() {
                    base.formIndex(after: &positions[i])
                    if positions[i] != base.endIndex {
                        finished = false
                        break
                    } else {
                        positions[i] = base.startIndex
                    }
                }

            }
            return finished ? nil : positions.map { base[$0] }
        }
    }

    package func makeIterator() -> Iterator {
        return Iterator(of: base, length: length)
    }
}
