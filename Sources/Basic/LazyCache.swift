/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Thread-safe lazily cached methods.
///
/// The `lazy` annotation in Swift does not result in a thread-safe accessor,
/// which can make it an easy source of hard-to-find concurrency races. This
/// class defines a wrapper designed to be used as an alternative for
/// `lazy`. Example usage:
///
/// ```
/// class Foo {
///     var bar: Int { return barCache.getValue(self) }
///     var barCache = LazyCache(someExpensiveMethod)
///
///     func someExpensiveMethod() -> Int { ... }
/// }
/// ```
///
/// See: https://bugs.swift.org/browse/SR-1042
//
// FIXME: This wrapper could benefit from local static variables, in which case
// we could embed the cache object inside the accessor.
public struct LazyCache<Class, T> {
    // FIXME: It would be nice to avoid a per-instance lock, but this type isn't
    // intended for creating large numbers of instances of. We also really want
    // a reader-writer lock or something similar here.
    private var lock = Lock()
    let body: (Class) -> () -> T
    var cachedValue: T?

    /// Create a lazy cache from a method value.
    public init(_ body: @escaping (Class) -> () -> T) {
        self.body = body
    }

    /// Get the cached value, computing it if necessary.
    public mutating func getValue(_ instance: Class) -> T {
        // FIXME: This is unfortunate, see note w.r.t. the lock.
        return lock.withLock {
            if let value = cachedValue {
                return value
            } else {
                let result = body(instance)()
                cachedValue = result
                return result
            }
        }
    }
}
