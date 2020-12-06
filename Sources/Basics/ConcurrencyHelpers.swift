/*
 This source file is part of the Swift.org open source project
 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

public struct ThreadSafeDictionary<Key, Value> where Key: Hashable {
    private var underlying: [Key: Value]
    private let lock = Lock()

    public init(_ seed: [Key: Value] = [:]) {
        self.underlying = seed
    }

    public subscript(key: Key) -> Value? {
        self.lock.withLock {
            self.underlying[key]
        }
    }

    @discardableResult
    public mutating func memoize(key: Key, _ body: () throws -> Value) rethrows -> Value {
        try self.underlying.memoize(key: key, lock: self.lock, body: body)
    }

    public mutating func clear() {
        self.lock.withLock {
            self.underlying.removeAll()
        }
    }
}

public struct ThreadSafeBox<Value> {
    private var underlying: Value?
    private let lock = Lock()

    public init() {}

    @discardableResult
    public mutating func memoize(_ body: () throws -> Value) rethrows -> Value {
        if let value = self.get() {
            return value
        }
        let value = try body()
        self.lock.withLock {
            self.underlying = value
        }
        return value
    }

    public mutating func clear() {
        self.lock.withLock {
            self.underlying = nil
        }
    }

    public func get() -> Value? {
        self.lock.withLock {
            self.underlying
        }
    }
}
