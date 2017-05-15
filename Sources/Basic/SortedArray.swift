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
        elements.append(contentsOf: newElements)
        elements.sort(by: areInIncreasingOrder)
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
