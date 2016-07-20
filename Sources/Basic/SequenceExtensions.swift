/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Sequence {
    /// Create an iterator over nested elements of the values provided by this iterator.
    ///
    /// - Parameters:
    ///    - nestedSequence: A closure supplying the nested sequence to iterate over for each element.
    public func makeNestedIterator<NestedElement,
                                   NestedSequence : Sequence
                                   where NestedSequence.Iterator.Element == NestedElement> (
            nestedSequence: (Iterator.Element) -> NestedSequence
    ) -> AnyIterator<NestedElement> {
        var iterator = makeIterator()
        var nestedIterator: NestedSequence.Iterator? = nil
        return AnyIterator { () -> NestedElement? in
            while true {
                // Consume the next element off of the current iterator, if available.
                if let next = nestedIterator?.next() {
                    return next
                }
                
                // Otherwise, we have exhaused the current iterator, get the next one.
                guard let element = iterator.next() else {
                    return nil
                }
                nestedIterator = nestedSequence(element).makeIterator()
            }
        }        
    }
}
