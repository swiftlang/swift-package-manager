/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

extension Collection {
    /// Returns the only element of the collection or nil.
    public var spm_only: Element? {
        return count == 1 ? self[startIndex] : nil
    }

    /// Prints the element of array to standard output stream.
    ///
    /// This method should be used for debugging only.
    public func spm_dump() {
        for element in self {
            print(element)
        }
    }
}

extension Collection where Element: Hashable {
    /// Returns a new list of element removing duplicate elements.
    ///
    /// Note: The order of elements is preseved.
    /// Complexity: O(n)
    public func spm_uniqueElements() -> [Element] {
        var set = Set<Element>()
        var result = [Element]()
        for element in self {
            if set.insert(element).inserted {
                result.append(element)
            }
        }
        return result
    }
}
