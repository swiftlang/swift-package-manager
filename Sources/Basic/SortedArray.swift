/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// An array which is always in sorted state.
public struct SortedArray<Element>: CustomStringConvertible {
    
    /// Storage for our elements.
    fileprivate var elements: [Element]
    
    /// A predicate that returns `true` if its first argument should be ordered
    /// before its second argument; otherwise, `false`.
    fileprivate let areInIncreasingOrder: (Element, Element) -> Bool
    
    /// Create an empty sorted array with given comparison predicate.
    public init(areInIncreasingOrder: @escaping (Element, Element) -> Bool) {
        self.elements = []
        self.areInIncreasingOrder = areInIncreasingOrder
    }

    /// Create a sorted array with the given sequence and comparison predicate.
    public init<S: Sequence>(
        _ newElements: S,
        areInIncreasingOrder: @escaping (Element, Element) -> Bool)
    where S.Iterator.Element == Element
    {
        self.elements = newElements.sorted(by: areInIncreasingOrder)
        self.areInIncreasingOrder = areInIncreasingOrder
    }
    
    /// Insert the given element, maintaining the sort order.
    public mutating func insert(_ newElement: Element) {
        let index = self.index(for: newElement)
        elements.insert(newElement, at: index)
    }
    
    /// Returns the index to insert the element in the sorted array using binary search.
    private func index(for element: Element) -> Index {
        
        if self.isEmpty {
            return 0
        }
        var (low, high) = (0, self.endIndex - 1)
        var mid = 0
        
        while low < high {
            mid = (low + high)/2
            if areInIncreasingOrder(self[mid], element) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        // At this point, low == high, low will never be greater than high, as low is incremented by just one or high is adjusted to mid.
        
        if areInIncreasingOrder(element, self[low]) {
            return low
        }
        
        return high + 1
    }
    
    /// Insert the given sequence, maintaining the sort order.
    public mutating func insert<S: Sequence>(contentsOf newElements: S) where S.Iterator.Element == Element {
        var newElements: Array = newElements.sorted(by: areInIncreasingOrder)
        guard !newElements.isEmpty else {
            return
        }
        guard !elements.isEmpty else {
            elements = newElements
            return
        }

        var lhsIndex = elements.endIndex - 1
        var rhsIndex = newElements.endIndex - 1

        elements.reserveCapacity(elements.count + newElements.count)

        // NOTE: If SortedArray moves to stdlib an _ArrayBuffer can be used
        // instead. This append can then be removed as _ArrayBuffer can be
        // resized without requiring instantiated elements.
        elements.append(contentsOf: newElements)

        var lhs = elements[lhsIndex], rhs = newElements[rhsIndex]

        // Equivalent to a merge sort, "pop" and append the max elemeent of
        // each array until either array is empty.
        for index in elements.indices.reversed() {
            if areInIncreasingOrder(lhs, rhs) {
                elements[index] = rhs
                rhsIndex -= 1
                guard rhsIndex >= newElements.startIndex else { break }
                rhs = newElements[rhsIndex]
            } else {
                elements[index] = lhs
                lhsIndex -= 1
                guard lhsIndex >= elements.startIndex else { break }
                lhs = elements[lhsIndex]
            }
        }

        // Any remaining new elements were smaller than all old elements
        // so the remaining new elements can safely replace the prefix.
        if rhsIndex >= newElements.startIndex {
            elements.replaceSubrange(
                newElements.startIndex ... rhsIndex,
                with: newElements[newElements.startIndex ... rhsIndex])
        }
    }

    /// Returns the values as an array.
    public var values: [Element] {
        return elements
    }
    
    public var description: String {
        return "<SortedArray: \(elements)>"
    }
}

extension SortedArray: RandomAccessCollection {
    public typealias Index = Int
    
    public var startIndex: Index {
        return elements.startIndex
    }
    
    public var endIndex: Index {
        return elements.endIndex
    }
    
    public func index(after i: Index) -> Index {
        return elements.index(after: i)
    }
    
    public func index(before i: Index) -> Index {
        return elements.index(before: i)
    }
    
    public subscript(position: Index) -> Element {
        return elements[position]
    }
}

extension SortedArray {
    public static func +=<S: Sequence>(lhs: inout SortedArray, rhs: S) where S.Iterator.Element == Element {
        lhs.insert(contentsOf: rhs)
    }
}

extension SortedArray where Element: Comparable {
    /// Create an empty sorted array with < as the comparison predicate.
    public init() {
		self.init(areInIncreasingOrder: <)
    }
}
