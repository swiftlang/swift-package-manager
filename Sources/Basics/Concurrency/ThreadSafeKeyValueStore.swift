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

import _Concurrency

import Synchronization

/// Thread-safe dictionary with async memoization
public actor ThrowingAsyncKeyValueMemoizer<Key: Hashable & Sendable, Value: Sendable> {
    var stored: [Key: Task<Value, Error>] = [:]

    public init() {
        self.stored = [:]
    }

    public func memoize(_ key: Key, body: @Sendable @escaping () async throws -> Value) async throws -> Value {
        guard let existingTask = self.stored[key] else {
            let newTask = Task {
                try await body()
            }
            self.stored[key] = newTask
            return try await newTask.value
        }
        return try await existingTask.value
    }
}

public actor AsyncKeyValueMemoizer<Key: Hashable & Sendable, Value: Sendable> {
    var stored: [Key: Task<Value, Never>] = [:]

    public init() {
        self.stored = [:]
    }

    public func memoize(_ key: Key, body: @Sendable @escaping () async -> Value) async -> Value {
        guard let existingTask = self.stored[key] else {
            let newTask = Task {
                await body()
            }
            self.stored[key] = newTask
            return await newTask.value
        }
        return await existingTask.value
    }
}

public actor AsyncThrowingValueMemoizer<Value: Sendable> {
    var stored: ValueStorage?

    enum ValueStorage {
    case inProgress([CheckedContinuation<Value, Error>])
    case complete(Result<Value, Error>)
    }

    public init() {}

    public func memoize(body: @Sendable () async throws -> Value) async throws -> Value {
        guard let stored else {
            self.stored = .inProgress([])
            let result: Result<Value, Error>
            do {
                result = try await .success(body())
            } catch {
                result = .failure(error)
            }
            if case .inProgress(let array) = self.stored {
                self.stored = .complete(result)
                array.forEach { $0.resume(with: result)}
            }
            return try result.get()
        }
        switch stored {

        case .inProgress(let existing):
            return try await withCheckedThrowingContinuation {
                self.stored = .inProgress(existing + [$0])
            }
        case .complete(let result):
            return try result.get()
        }
    }
}

/// Thread-safe dictionary like structure.
public final class ThreadSafeKeyValueStore<Key: Sendable, Value: Sendable> where Key: Hashable {
    private let underlying: Mutex<[Key: Value]>

    public init(_ seed: [Key: Value] = [:]) {
        self.underlying = Mutex(seed)
    }

    public func get() -> [Key: Value] {
        self.underlying.withLock { $0 }
    }

    public subscript(key: Key) -> Value? {
        get {
            self.underlying.withLock {
                $0[key]
            }
        } set {
            self.underlying.withLock {
                $0[key] = newValue
            }
        }
    }

    @discardableResult
    public func memoize(_ key: Key, body: () throws -> Value) rethrows -> Value {
        try self.underlying.withLock {
            try $0.memoize(key: key, body: body)
        }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        self.underlying.withLock {
            $0.removeValue(forKey: key)
        }
    }

    @discardableResult
    public func clear() -> [Key: Value] {
        self.underlying.withLock { underlying in
            let existing = underlying
            underlying.removeAll()
            return existing
        }
    }

    public var count: Int {
        self.underlying.withLock { $0.count }
    }

    public var isEmpty: Bool {
        self.underlying.withLock { $0.isEmpty }
    }

    public func contains(_ key: Key) -> Bool {
        self.underlying.withLock {
            $0.keys.contains(key)
        }
    }

    public func map<T: Sendable>(_ transform: ((key: Key, value: Value)) throws -> T) rethrows -> [T] {
        try self.underlying.withLock {
            try $0.map(transform)
        }
    }

    public func mapValues<T: Sendable>(_ transform: (Value) throws -> T) rethrows -> [Key: T] {
        try self.underlying.withLock {
            try $0.mapValues(transform)
        }
    }
}

extension ThreadSafeKeyValueStore: Sendable {}
