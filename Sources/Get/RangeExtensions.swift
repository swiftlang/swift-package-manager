/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription

// FIXME: workaround for inability to constrain the extension to `Bound == Version`.
public protocol _VersionProtocol {}
extension Version : _VersionProtocol {}

extension Range where Bound : _VersionProtocol {

    /**
     - Returns: A new Range with startIndex and endIndex constrained such that
     the returned range is entirely within this Range and the provided Range.
     If the two ranges do not overlap at all returns `nil`.
     */
    public func constrained(to constraint: Range) -> Range? {
        let start = Swift.max(self.lowerBound, constraint.lowerBound)
        let end = Swift.min(self.upperBound, constraint.upperBound)
        if start < end {
            return start..<end
        } else {
            return nil
        }
    }
}
