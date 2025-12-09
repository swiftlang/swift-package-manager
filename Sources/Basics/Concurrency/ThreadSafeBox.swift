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

/// Thread-safe value boxing structure that provides synchronized access to a wrapped value.
@dynamicMemberLookup
public final class ThreadSafeBox<Value> {
    private var underlying: Value
    private let lock = NSLock()

    /// Creates a new thread-safe box with the given initial value.
    ///
    /// - Parameter seed: The initial value to store in the box.
    public init(_ seed: Value) {
        self.underlying = seed
    }

    /// Atomically mutates the stored value by applying a transformation function.
    ///
    /// The transformation function receives the current value and returns a new value
    /// to replace it. The entire operation is performed under a lock to ensure atomicity.
    ///
    /// - Parameter body: A closure that takes the current value and returns a new value.
    /// - Throws: Any error thrown by the transformation function.
    public func mutate(body: (Value) throws -> Value) rethrows {
        try self.lock.withLock {
            let value = try body(self.underlying)
            self.underlying = value
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
        try self.lock.withLock {
            try body(&self.underlying)
        }
    }

    /// Atomically retrieves the current value from the box.
    ///
    /// - Returns: A copy of the current value stored in the box.
    public func get() -> Value {
        self.lock.withLock {
            self.underlying
        }
    }

    /// Atomically replaces the current value with a new value.
    ///
    /// - Parameter newValue: The new value to store in the box.
    public func put(_ newValue: Value) {
        self.lock.withLock {
            self.underlying = newValue
        }
    }

    /// Provides thread-safe read-only access to properties of the wrapped value.
    ///
    /// This subscript allows you to access properties of the wrapped value using
    /// dot notation while maintaining thread safety.
    ///
    /// - Parameter keyPath: A key path to a property of the wrapped value.
    /// - Returns: The value of the specified property.
    public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
        self.lock.withLock {
            self.underlying[keyPath: keyPath]
        }
    }

    /// Provides thread-safe read-write access to properties of the wrapped value.
    ///
    /// - Parameter keyPath: A writable key path to a property of the wrapped value.
    /// - Returns: The value of the specified property when getting.
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> T {
        get {
            self.lock.withLock {
                self.underlying[keyPath: keyPath]
            }
        }
        set {
            self.lock.withLock {
                self.underlying[keyPath: keyPath] = newValue
            }
        }
    }
}

// Extension for optional values to support empty initialization
extension ThreadSafeBox {
    /// Creates a new thread-safe box initialized with nil for optional value types.
    ///
    /// This convenience initializer is only available when the wrapped value type is optional.
    public convenience init<Wrapped>() where Value == Wrapped? {
        self.init(nil)
    }

    /// Takes the stored optional value, setting it to nil.
    /// - Returns: The previously stored value, or nil if none was present.
    public func takeValue<Wrapped>() -> Value where Value == Wrapped? {
        self.lock.withLock {
            guard let value = self.underlying else { return nil }
            self.underlying = nil
            return value
        }
    }

    /// Atomically sets the stored optional value to nil.
    ///
    /// This method is only available when the wrapped value type is optional.
    public func clear<Wrapped>() where Value == Wrapped? {
        self.lock.withLock {
            self.underlying = nil
        }
    }

    /// Atomically retrieves the stored value, returning a default if nil.
    ///
    /// This method is only available when the wrapped value type is optional.
    ///
    /// - Parameter defaultValue: The value to return if the stored value is nil.
    /// - Returns: The stored value if not nil, otherwise the default value.
    public func get<Wrapped>(default defaultValue: Wrapped) -> Wrapped where Value == Wrapped? {
        self.lock.withLock {
            self.underlying ?? defaultValue
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
    public func memoize<Wrapped>(body: () throws -> Wrapped) rethrows -> Wrapped where Value == Wrapped? {
        try self.lock.withLock {
            if let value = self.underlying {
                return value
            }
            let value = try body()
            self.underlying = value
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
    public func memoizeOptional<Wrapped>(body: () throws -> Wrapped?) rethrows -> Wrapped? where Value == Wrapped? {
        try self.lock.withLock {
            if let value = self.underlying {
                return value
            }
            let value = try body()
            self.underlying = value
            return value
        }
    }
}

extension ThreadSafeBox where Value == Int {
    /// Atomically increments the stored integer value by 1.
    ///
    /// This method is only available when the wrapped value type is Int.
    public func increment() {
        self.lock.withLock {
            self.underlying = self.underlying + 1
        }
    }

    /// Atomically decrements the stored integer value by 1.
    ///
    /// This method is only available when the wrapped value type is Int.
    public func decrement() {
        self.lock.withLock {
            self.underlying = self.underlying - 1
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

extension ThreadSafeBox: @unchecked Sendable where Value: Sendable {}
