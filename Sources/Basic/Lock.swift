/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.Lock
import class Foundation.Condition

/// A simple lock wrapper.
public struct Lock {
    private var _lock = Foundation.Lock()

    /// Create a new lock.
    public init() {
    }
    
    /// Execute the given block while holding the lock.
    public mutating func withLock<T> (_ body: @noescape () throws -> T) rethrows -> T {
        _lock.lock()
        defer { _lock.unlock() }
        return try body()
    }
}

public extension Condition {
    /// A helper method to execute the given body while condition is locked.
    public func whileLocked<T>(_ body: @noescape () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
