/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A double linked list.
public final class LinkedList<T> {

    /// Represents a single node in the linked list.
    public final class Node: CustomStringConvertible {
        /// The value stored in the node.
        public let value: T

        /// The next node.
        fileprivate(set) var next: Node?

        /// The previous node.
        weak fileprivate(set) var previous: Node?

        public init(_ value: T) {
            self.value = value
        }

        public var description: String {
            return "node(\(value))"
        }
    }

    /// The head of the linked list.
    fileprivate var head: Node?

    /// The tail of the linked list.
    fileprivate var tail: Node?

    /// Append the given node to end of the linked list.
    public func append(_ newNode: Node) {
        if let lastNode = tail {
            newNode.previous = lastNode
            lastNode.next = newNode
            tail = newNode
        } else {
            tail = newNode
            head = newNode
        }
    }

    /// Prepend the given node to start of the linked list.
    public func prepend(_ newNode: Node) {
        if let firstNode = head {
            newNode.next = firstNode
            firstNode.previous = newNode
            head = newNode
        } else {
            tail = newNode
            head = newNode
        }
    }

    /// Make the given node the head.
    ///
    /// The node must be present in the linked list.
    public func makeHead(_ node: Node) {
        assert(self.first(where: { $0 === node }) != nil, "Node not present in linked list.")

        // Fast path.
        if node === head { return }

        // Connect previous and next nodes.
        let next = node.next
        let previous = node.previous

        previous?.next = next
        next?.previous = previous

        // Make this node the head.
        node.previous = nil
        node.next = head

        head?.previous = node
        head = node
    }

    /// Remove the given node from linked list.
    public func remove(_ node: Node) {
        assert(self.first(where: { $0 === node }) != nil, "Node not present in linked list.")

        // Connect previous and next nodes.
        let next = node.next
        let previous = node.previous

        previous?.next = next
        next?.previous = previous

        // Update head and tail, if needed.
        if node === head {
            head = next
        }
        if node === tail {
            tail = previous
        }
    }
}

extension LinkedList: CustomStringConvertible {

    public var description: String {
        var str = ""
        for node in self {
            str += "\(node)"
            str += " -> "
        }
        if str.characters.count >= 4 {
            str = str[str.startIndex..<str.index(str.endIndex, offsetBy: -4)]
        }
        print(str)
    }
}

extension LinkedList: Sequence {
    public func makeIterator() -> AnyIterator<Node> {
        var itr = head
        return AnyIterator {
            defer { itr = itr?.next }
            return itr
        }
    }
}
