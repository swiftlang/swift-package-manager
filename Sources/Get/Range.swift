/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Version

extension Range where Bound == Version {

    /**
     - Returns: A new Range with startIndex and endIndex constrained such that
     the returned range is entirely within this Range and the provided Range.
     If the two ranges do not overlap at all returns `nil`.
     */
    func constrain(to constraint: Range) -> Range? {
        let start = Swift.max(self.lowerBound, constraint.lowerBound)
        let end = Swift.min(self.upperBound, constraint.upperBound)
        if start < end {
            return start..<end
        } else {
            return nil
        }
    }
}
