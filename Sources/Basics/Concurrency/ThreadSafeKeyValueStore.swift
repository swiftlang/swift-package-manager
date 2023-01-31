//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Foundation.NSLock

/// Thread-safe dictionary like structure
public final class ThreadSafeKeyValueStore<Key, Value> where Key: Hashable {
    private var underlying: [Key: Value]
    private let lock = NSLock()

    public init(_ seed: [Key: Value] = [:]) {
        self.underlying = seed
    }

    public func get() -> [Key: Value] {
        self.lock.withLock {
            self.underlying
        }
    }

    public subscript(key: Key) -> Value? {
        get {
            self.lock.withLock {
                self.underlying[key]
            }
        } set {
            self.lock.withLock {
                self.underlying[key] = newValue
            }
        }
    }

    @discardableResult
    public func memoize(_ key: Key, body: () throws -> Value) rethrows -> Value {
        try self.lock.withLock {
            try self.underlying.memoize(key: key, body: body)
        }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        self.lock.withLock {
            self.underlying.removeValue(forKey: key)
        }
    }

    @discardableResult
    public func clear() -> [Key: Value] {
        self.lock.withLock {
            let underlying = self.underlying
            self.underlying.removeAll()
            return underlying
        }
    }

    public var count: Int {
        self.lock.withLock {
            self.underlying.count
        }
    }

    public var isEmpty: Bool {
        self.lock.withLock {
            self.underlying.isEmpty
        }
    }

    public func contains(_ key: Key) -> Bool {
        self.lock.withLock {
            self.underlying.keys.contains(key)
        }
    }

    public func map<T>(_ transform: ((key: Key, value: Value)) throws -> T) rethrows -> [T] {
        try self.lock.withLock {
            try self.underlying.map(transform)
        }
    }

    public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> [Key: T] {
        try self.lock.withLock {
            try self.underlying.mapValues(transform)
        }
    }

    public func forEach(_ iterate: ((Key, Value)) throws -> ()) rethrows {
        try self.lock.withLock {
            try self.underlying.forEach(iterate)
        }
    }
}

#if swift(<5.7)
extension ThreadSafeKeyValueStore: UnsafeSendable {}
#else
extension ThreadSafeKeyValueStore: @unchecked Sendable {}
#endif
