/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// This class can be used as a shared queue between multiple threads providing
/// thread safe APIs.
public final class SynchronizedQueue<Element> {
    /// Storage for queued elements.
    private var storage: [Element]

    /// Condition variable to block the thread trying dequeue and queue is empty.
    private var notEmptyCondition: Condition

    /// Create a default instance of queue.
    public init() {
        storage = []
        notEmptyCondition = Condition()
    }

    /// Safely enqueue an element to end of the queue and signals a thread blocked on dequeue.
    ///
    /// - Parameters:
    ///     - element: The element to be enqueued.
    public func enqueue(_ element: Element) {
        notEmptyCondition.whileLocked {
            storage.append(element)
            // Signal a thread blocked on dequeue.
            notEmptyCondition.signal()
        }
    }

    /// Dequeue an element from front of the queue. Blocks the calling thread until an element is available.
    ///
    /// - Returns: First element in the queue.
    public func dequeue() -> Element {
        return notEmptyCondition.whileLocked {
            // Wait until we have an element available in the queue.
            while storage.isEmpty {
                notEmptyCondition.wait()
            }

            // FIXME: This is O(n) operation, optimize.
            return storage.removeFirst()
        }
    }
}
