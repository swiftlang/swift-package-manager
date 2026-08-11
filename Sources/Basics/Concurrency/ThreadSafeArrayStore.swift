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

import Synchronization

/// Thread-safe array like structure
public final class ThreadSafeArrayStore<Value: Sendable> {
    private let underlying: Mutex<[Value]>

    public init(_ seed: [Value] = []) {
        self.underlying = Mutex(seed)
    }

    public subscript(index: Int) -> Value? {
        self.underlying.withLock {
            $0[index]
        }
    }

    public func get() -> [Value] {
        self.underlying.withLock { $0 }
    }

    @discardableResult
    public func clear() -> [Value] {
        self.underlying.withLock { underlying in
            let existing = underlying
            underlying.removeAll()
            return existing
        }
    }

    @discardableResult
    public func append(_ item: Value) -> Int {
        self.underlying.withLock {
            $0.append(item)
            return $0.count
        }
    }

    @discardableResult
    public func append(contentsOf items: [Value]) -> Int {
        self.underlying.withLock {
            $0.append(contentsOf: items)
            return $0.count
        }
    }

    public var count: Int {
        self.underlying.withLock { $0.count }
    }

    public var isEmpty: Bool {
        self.underlying.withLock { $0.isEmpty }
    }

    public func map<NewValue: Sendable>(_ transform: (Value) -> NewValue) -> [NewValue] {
        self.underlying.withLock {
            $0.map(transform)
        }
    }

    public func compactMap<NewValue: Sendable>(_ transform: (Value) throws -> NewValue?) rethrows -> [NewValue] {
        try self.underlying.withLock {
            try $0.compactMap(transform)
        }
    }
}

extension ThreadSafeArrayStore: Sendable {}
