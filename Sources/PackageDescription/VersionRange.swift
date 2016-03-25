/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public struct VersionRange {
    public let range: Range<Version>
    public let start: Version
    public let end: Version

    public func constrain(to constraint: VersionRange) -> VersionRange? {
        let start = Swift.max(self.range.startIndex, constraint.range.startIndex)
        let end = Swift.min(self.range.endIndex, constraint.range.endIndex)
        if start < end {
            return start..<end
        } else {
            return nil
        }
    }
}

// MARK: Equatable

extension VersionRange: Equatable {}

public func ==(lhs: VersionRange, rhs: VersionRange) -> Bool {
    return lhs.range == rhs.range
}

// MARK: Range Operator

public func ...(start: Version, end: Version) -> VersionRange {
    if start > end {
        //TODO: add proper Error Handling
        print("Error! \(start) Version is bigger than \(end)")
    }
    return VersionRange(range: start...end, start: start, end: end)
}

public func ..<(start: Version, end: Version) -> VersionRange {
    if start > end {
        //TODO: add proper Error Handling
        print("Error! \(start) Version is bigger than \(end)")
    }
    return VersionRange(range: start..<end, start: start, end: end)
}

