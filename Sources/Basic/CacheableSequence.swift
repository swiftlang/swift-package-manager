/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Wrapper for caching an arbitrary sequnce.
public final class CacheableSequence<T: Sequence>: Sequence {
    public typealias Element = T.Element
    public typealias Iterator = CacheableSequenceIterator<T>

    /// The list of consumed items.
    fileprivate var items: [Element] = []
    
    /// An iterator on the underlying sequence, until complete.
    fileprivate var it: T.Iterator?
    
    public init(_ sequence: T) {
        self.it = sequence.makeIterator()
    }
    
    public func makeIterator() -> Iterator {
        return CacheableSequenceIterator(self)
    }

    /// Get the item at the given index.
    ///
    /// The index must either be at most one past the number of already captured
    /// items.
    fileprivate subscript(_ index: Int) -> Element? {
        assert(index >= 0 && index <= items.count)
        if index < items.count {
            return items[index]
        } else if self.it != nil {
            // If we still have an iterator, attempt to consume a new item.
            guard let item = it!.next() else {
                // We reached the end of the sequence, we can discard the iterator.
                self.it = nil
                return nil
            }
            items.append(item)
            return items[index]
        } else {
            return nil
        }
    }
}

/// An iterator for a CacheableSequence.
public final class CacheableSequenceIterator<T: Sequence>: IteratorProtocol {
    public typealias Element = T.Element
    
    /// The index of the iterator.
    var index = 0

    /// The sequence being iterated.
    let sequence: CacheableSequence<T>
    
    init(_ sequence: CacheableSequence<T>) {
        self.sequence = sequence
    }

    public func next() -> Element? {
        if let item = self.sequence[index] {
            index += 1
            return item
        }
        return nil
    }
}
