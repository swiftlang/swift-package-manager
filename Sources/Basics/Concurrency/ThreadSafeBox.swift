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

/// Thread-safe value boxing structure that provides synchronized access to a wrapped value.
@dynamicMemberLookup
public final class ThreadSafeBox<Value: Sendable> {
    private let underlying: Mutex<Value>

    /// Creates a new thread-safe box with the given initial value.
    ///
    /// - Parameter seed: The initial value to store in the box.
    public init(_ seed: Value) {
        self.underlying = Mutex(seed)
    }

    /// Atomically mutates the stored value by applying a transformation function.
    ///
    /// The transformation function receives the current value and returns a new value
    /// to replace it. The entire operation is performed under a lock to ensure atomicity.
    ///
    /// - Parameter body: A closure that takes the current value and returns a new value.
    /// - Throws: Any error thrown by the transformation function.
    public func mutate(body: (Value) throws -> Value) rethrows {
        try self.underlying.withLock { value in
            value = try body(value)
        }
    }

    /// Atomically mutates the stored value by applying an in-place transformation.
    ///
    /// The transformation function receives an inout reference to the current value,
    /// allowing direct modification. The entire operation is performed under a lock
    /// to ensure atomicity.
    ///
    /// - Parameter body: A closure that receives an inout reference to the current value.
    /// - Throws: Any error thrown by the transformation function.
    public func mutate(body: (inout Value) throws -> Void) rethrows {
        try self.underlying.withLock {
            try body(&$0)
        }
    }

    /// Atomically retrieves the current value from the box.
    ///
    /// - Returns: A copy of the current value stored in the box.
    public func get() -> Value {
        self.underlying.withLock { $0 }
    }

    /// Atomically replaces the current value with a new value.
    ///
    /// - Parameter newValue: The new value to store in the box.
    public func put(_ newValue: Value) {
        self.underlying.withLock {
            $0 = newValue
        }
    }

    /// Provides thread-safe read-only access to properties of the wrapped value.
    ///
    /// This subscript allows you to access properties of the wrapped value using
    /// dot notation while maintaining thread safety.
    ///
    /// - Parameter keyPath: A key path to a property of the wrapped value.
    /// - Returns: The value of the specified property.
    public subscript<T: Sendable>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
        self.underlying.withLock {
            $0[keyPath: keyPath]
        }
    }

    /// Provides thread-safe read-write access to properties of the wrapped value.
    ///
    /// - Parameter keyPath: A writable key path to a property of the wrapped value.
    /// - Returns: The value of the specified property when getting.
    public subscript<T: Sendable>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> T {
        get {
            self.underlying.withLock {
                $0[keyPath: keyPath]
            }
        }
        set {
            self.underlying.withLock {
                $0[keyPath: keyPath] = newValue
            }
        }
    }
}

// Extension for optional values to support empty initialization
extension ThreadSafeBox {
    /// Creates a new thread-safe box initialized with nil for optional value types.
    ///
    /// This convenience initializer is only available when the wrapped value type is optional.
    public convenience init<Wrapped: Sendable>() where Value == Wrapped? {
        self.init(nil)
    }

    /// Takes the stored optional value, setting it to nil.
    /// - Returns: The previously stored value, or nil if none was present.
    public func takeValue<Wrapped: Sendable>() -> Value where Value == Wrapped? {
        self.underlying.withLock { underlying in
            guard let value = underlying else { return nil }
            underlying = nil
            return value
        }
    }

    /// Atomically sets the stored optional value to nil.
    ///
    /// This method is only available when the wrapped value type is optional.
    public func clear<Wrapped: Sendable>() where Value == Wrapped? {
        self.underlying.withLock {
            $0 = nil
        }
    }

    /// Atomically retrieves the stored value, returning a default if nil.
    ///
    /// This method is only available when the wrapped value type is optional.
    ///
    /// - Parameter defaultValue: The value to return if the stored value is nil.
    /// - Returns: The stored value if not nil, otherwise the default value.
    public func get<Wrapped: Sendable>(default defaultValue: Wrapped) -> Wrapped where Value == Wrapped? {
        self.underlying.withLock {
            $0 ?? defaultValue
        }
    }

    /// Atomically computes and caches a value if not already present.
    ///
    /// If the box already contains a non-nil value, that value is returned immediately.
    /// Otherwise, the provided closure is executed to compute the value, which is then
    /// stored and returned. This method is only available when the wrapped value type is optional.
    ///
    /// - Parameter body: A closure that computes the value to store if none exists.
    /// - Returns: The cached value or the newly computed value.
    /// - Throws: Any error thrown by the computation closure.
    @discardableResult
    public func memoize<Wrapped: Sendable>(body: () throws -> Wrapped) rethrows -> Wrapped
        where Value == Wrapped?
    {
        try self.underlying.withLock { underlying in
            if let value = underlying {
                return value
            }
            let value = try body()
            underlying = value
            return value
        }
    }

    /// Atomically computes and caches an optional value if not already present.
    ///
    /// If the box already contains a non-nil value, that value is returned immediately.
    /// Otherwise, the provided closure is executed to compute the value, which is then
    /// stored and returned. This method is only available when the wrapped value type is optional.
    ///
    /// If the returned value is `nil` subsequent calls to `memoize` or `memoizeOptional` will
    /// re-execute the closure.
    ///
    /// - Parameter body: A closure that computes the optional value to store if none exists.
    /// - Returns: The cached value or the newly computed value (which may be nil).
    /// - Throws: Any error thrown by the computation closure.
    @discardableResult
    public func memoizeOptional<Wrapped: Sendable>(body: () throws -> Wrapped?) rethrows -> Wrapped?
        where Value == Wrapped?
    {
        try self.underlying.withLock { underlying in
            if let value = underlying {
                return value
            }
            let value = try body()
            underlying = value
            return value
        }
    }
}

extension ThreadSafeBox where Value == Int {
    /// Atomically increments the stored integer value by 1.
    ///
    /// This method is only available when the wrapped value type is Int.
    public func increment() {
        self.underlying.withLock {
            $0 += 1
        }
    }

    /// Atomically decrements the stored integer value by 1.
    ///
    /// This method is only available when the wrapped value type is Int.
    public func decrement() {
        self.underlying.withLock {
            $0 -= 1
        }
    }
}

extension ThreadSafeBox where Value == String {
    /// Atomically appends a string to the stored string value.
    ///
    /// This method is only available when the wrapped value type is String.
    ///
    /// - Parameter value: The string to append to the current stored value.
    public func append(_ value: String) {
        self.mutate { existingValue in
            existingValue + value
        }
    }
}

extension ThreadSafeBox: Sendable {}
