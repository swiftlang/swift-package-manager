/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch

/// A LRU Cache.
///
/// This class is thread safe.
///
/// This class evicts least recently used elements in the cache when the number
/// of elements reaches load factor * capacity.
// FIXME: Add persistence.
final class LRUCache<Key: Hashable, Value> {

    /// The type for the linked list node.
    private typealias LinkedListNode = LinkedList<(Key, Value)>.Node<(Key, Value)>

    /// The linked list to maintain the LRU data.
    private let lruDataList = LinkedList<(Key, Value)>()

    /// The backing store of the cache O(1).
    private var store: [Key: LinkedListNode]

    /// Queue to protect concurrent mutations to the cache.
    private let queue = DispatchQueue(label: "org.swift.swiftpm.lru-cache")

    /// The number of entries that should be generally kept by the cache.
    public let capacity: Int

    /// Create a cache with given capacity.
    public init(capacity: Int = 100) {
        self.capacity = capacity
        store = [:]
    }

    /// Get and set a value for the given key.
    public subscript(_ key: Key) -> Value? {
        get {
            return get(for: key)
        } set {
            add(key: key, value: newValue)
        }
    }

    /// Add a key value pair.
    ///
    /// Complexity: O(1) on average.
    public func add(key: Key, value: Value?) {
        queue.sync {
            defer { evict() }

            // Remove the old node.
            if let oldNode = store[key] {
                store[key] = nil
                lruDataList.remove(oldNode)
            }

            // If value is nil, we're done.
            guard let value = value else {
                return
            }

            // Add new node.
            let nodeValue = LinkedListNode((key, value))
            lruDataList.prepend(nodeValue)
            store[key] = nodeValue
        }
    }

    /// Returns value for the key, if present in cache.
    ///
    /// Complexity: O(1) on average.
    public func get(for key: Key) -> Value? {
        return queue.sync {
            defer { evict() }
            guard let node = store[key] else {
                return nil
            }
            lruDataList.makeHead(node)
            return node.value.1
        }
    }

    /// The number od entries in the cache.
    public var count: Int {
        return queue.sync {
            store.count
        }
    }

    /// Evict the extra accumulated cache entries.
    private func evict() {
        guard Double(store.count) >= 1.75 * Double(capacity) else {
            return
        }

        // Collect the nodes we need to delete.
        var nodesToDelete = [LinkedListNode]()
        for (idx, node) in lruDataList.enumerated() {
            if idx >= capacity {
                nodesToDelete.append(node)
            }
        }

        // Remove the entry from store and the linked list.
        for node in nodesToDelete {
            store[node.value.0] = nil
            lruDataList.remove(node)
        }
    }

    /// Print the LRU linked list.
    ///
    /// Note: For debug purposes only.
    public func dumpLRUList() {
        lruDataList.dump()
    }
}
