/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Range where Element: BidirectionalIndex, Element: Comparable {

    /**
     - Returns: A new Range with startIndex and endIndex constrained such that
     the returned range is entirely within this Range and the provided Range.
     If the two ranges do not overlap at all returns `nil`.
     */
    func constrain(to constraint: Range) -> Range? {
        let start = Swift.max(self.startIndex, constraint.startIndex)
        let end = Swift.min(self.endIndex, constraint.endIndex)
        if start < end {
            return start..<end
        } else {
            return nil
        }
    }
}
