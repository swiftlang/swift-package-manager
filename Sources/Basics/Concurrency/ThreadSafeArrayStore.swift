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

extension ThreadSafeArrayStore: @unchecked Sendable where Value: Sendable {}
