//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import class Foundation.NSLock
import class Foundation.ProcessInfo
import enum TSCBasic.ProcessEnv
import func TSCBasic.tsc_await

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
}

/// Thread-safe array like structure
public final class ThreadSafeArrayStore<Value> {
    private var underlying: [Value]
    private let lock = NSLock()

    public init(_ seed: [Value] = []) {
        self.underlying = seed
    }

    public subscript(index: Int) -> Value? {
        self.lock.withLock {
            self.underlying[index]
        }
    }

    public func get() -> [Value] {
        self.lock.withLock {
            self.underlying
        }
    }

    @discardableResult
    public func clear() -> [Value] {
        self.lock.withLock {
            let underlying = self.underlying
            self.underlying.removeAll()
            return underlying
        }
    }

    @discardableResult
    public func append(_ item: Value) -> Int {
        self.lock.withLock {
            self.underlying.append(item)
            return self.underlying.count
        }
    }

    @discardableResult
    public func append(contentsOf items: [Value]) -> Int {
        self.lock.withLock {
            self.underlying.append(contentsOf: items)
            return self.underlying.count
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

    public func map<NewValue>(_ transform: (Value) -> NewValue) -> [NewValue] {
        self.lock.withLock {
            self.underlying.map(transform)
        }
    }

    public func compactMap<NewValue>(_ transform: (Value) throws -> NewValue?) rethrows -> [NewValue] {
        try self.lock.withLock {
            try self.underlying.compactMap(transform)
        }
    }
}

/// Thread-safe value boxing structure
@dynamicMemberLookup
public final class ThreadSafeBox<Value> {
    private var underlying: Value?
    private let lock = NSLock()

    public init() {}

    public init(_ seed: Value) {
        self.underlying = seed
    }

    @discardableResult
    public func memoize(body: () throws -> Value) rethrows -> Value {
        if let value = self.get() {
            return value
        }
        let value = try body()
        self.lock.withLock {
            self.underlying = value
        }
        return value
    }

    public func clear() {
        self.lock.withLock {
            self.underlying = nil
        }
    }

    public func get() -> Value? {
        self.lock.withLock {
            self.underlying
        }
    }

    public func get(`default`: Value) -> Value {
        self.lock.withLock {
            self.underlying ?? `default`
        }
    }

    public func put(_ newValue: Value) {
        self.lock.withLock {
            self.underlying = newValue
        }
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T? {
        self.lock.withLock {
            self.underlying?[keyPath: keyPath]
        }
    }

    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T?>) -> T? {
        get {
            self.lock.withLock {
                self.underlying?[keyPath: keyPath]
            }
        }
        set {
            self.lock.withLock {
                if var value = self.underlying {
                    value[keyPath: keyPath] = newValue
                }
            }
        }
    }
}

extension ThreadSafeBox where Value == Int {
    public func increment() {
        self.lock.withLock {
            if let value = self.underlying {
                self.underlying = value + 1
            }
        }
    }
    public func decrement() {
        self.lock.withLock {
            if let value = self.underlying {
                self.underlying = value - 1
            }
        }
    }
}

public enum Concurrency {
    public static var maxOperations: Int {
        return ProcessEnv.vars["SWIFTPM_MAX_CONCURRENT_OPERATIONS"].flatMap(Int.init) ?? ProcessInfo.processInfo.activeProcessorCount
    }
}

// FIXME: mark as deprecated once async/await is available
// @available(*, deprecated, message: "replace with async/await when available")
@inlinable
public func temp_await<T, ErrorType>(_ body: (@escaping (Result<T, ErrorType>) -> Void) -> Void) throws -> T {
    return try tsc_await(body)
}

// FIXME: mark as deprecated once async/await is available
// @available(*, deprecated, message: "replace with async/await when available")
@inlinable
public func temp_await<T>(_ body: (@escaping (T) -> Void) -> Void) -> T {
    return tsc_await(body)
}

public extension DispatchQueue {
    // a shared concurrent queue for running concurrent asynchronous operations
    static var sharedConcurrent = DispatchQueue(label: "swift.org.swiftpm.shared.concurrent", attributes: .concurrent)
}
