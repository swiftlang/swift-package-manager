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
        elements.append(newElement)
        // FIXME: It is way too costly to sort again for just one element.
        // We can use binary search to find the index for this element.
        elements.sort(by: areInIncreasingOrder)
    }
    
    /// Insert the given sequence, maintaining the sort order.
    public mutating func insert<S: Sequence>(contentsOf newElements: S) where S.Iterator.Element == Element {
        elements.append(contentsOf: newElements)
        elements.sort(by: areInIncreasingOrder)
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
