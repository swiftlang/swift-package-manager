/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// An ordered set is an ordered collection of instances of `Element` in which
/// uniqueness of the objects is guaranteed.
public struct OrderedSet<E: Hashable>: Equatable, Collection {
    public typealias Element = E
    public typealias Index = Int
    public typealias Indices = CountableRange<Int>

    private var array: [Element]
    private var set: Set<Element>

    /// Creates an empty ordered set.
    public init() {
        self.array = []
        self.set = Set()
    }

    /// Creates an ordered set with the contents of `array`.
    ///
    /// If an element occurs more than once in `element`, only the first one
    /// will be included.
    public init(_ array: [Element]) {
        self.init()
        for element in array {
            append(element)
        }
    }

    // MARK: Working with an ordered set

    /// The number of elements the ordered set stores.
    public var count: Int { return array.count }

    /// Returns `true` if the set is empty.
    public var isEmpty: Bool { return array.isEmpty }

    /// Returns the contents of the set as an array.
    public var contents: [Element] { return array }

    /// Returns `true` if the ordered set contains `member`.
    public func contains(_ member: Element) -> Bool {
        return set.contains(member)
    }

    /// Adds an element to the ordered set.
    ///
    /// If it already contains the element, then the set is unchanged.
    ///
    /// - returns: True if the item was inserted.
    @discardableResult
    public mutating func append(_ newElement: Element) -> Bool {
        let inserted = set.insert(newElement).inserted
        if inserted {
            array.append(newElement)
        }
        return inserted
    }

    /// Remove and return the element at the end of the ordered set.
    public mutating func removeLast() -> Element {
        let lastElement = array.removeLast()
        set.remove(lastElement)
        return lastElement
    }

    /// Remove all elements.
    public mutating func removeAll(keepingCapacity keepCapacity: Bool) {
        array.removeAll(keepingCapacity: keepCapacity)
        set.removeAll(keepingCapacity: keepCapacity)
    }
}

extension OrderedSet: ExpressibleByArrayLiteral {
    /// Create an instance initialized with `elements`.
    ///
    /// If an element occurs more than once in `element`, only the first one
    /// will be included.
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension OrderedSet: RandomAccessCollection {
    public var startIndex: Int { return contents.startIndex }
    public var endIndex: Int { return contents.endIndex }
    public subscript(index: Int) -> Element {
      return contents[index]
    }
}

public func == <T>(lhs: OrderedSet<T>, rhs: OrderedSet<T>) -> Bool {
    return lhs.contents == rhs.contents
}
