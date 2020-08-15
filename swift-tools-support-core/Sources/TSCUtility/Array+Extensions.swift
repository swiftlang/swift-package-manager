// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors


extension Array {
    /// Make several slices out of a given array.
    /// - Returns:
    ///   An array of slices of `maxStride` elements each.
    @inlinable
    public func tsc_sliceBy(maxStride: Int) -> [ArraySlice<Element>] {
        let elementsCount = self.count
        let groupsCount = (elementsCount + maxStride - 1) / maxStride
        return (0..<groupsCount).map({ n in
            self[n*maxStride..<Swift.min(elementsCount, (n+1)*maxStride)]
        })
    }
}
