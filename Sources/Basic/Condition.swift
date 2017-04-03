/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// A simple condition wrapper.
public struct Condition {
    private let _condition = NSCondition()

    /// Create a new condition.
    public init() {}

    /// Wait for the condition to become available.
    public func wait() {
        _condition.wait()
    }

    /// Blocks the current thread until the condition is signaled or the specified time limit is reached.
    ///
    /// - Returns: true if the condition was signaled; otherwise, false if the time limit was reached.
    public func wait(until limit: Date) -> Bool {
        return _condition.wait(until: limit)
    }

    /// Signal the availability of the condition (awake one thread waiting on
    /// the condition).
    public func signal() {
        _condition.signal()
    }

    /// Broadcast the availability of the condition (awake all threads waiting
    /// on the condition).
    public func broadcast() {
        _condition.broadcast()
    }

    /// A helper method to execute the given body while condition is locked.
    public func whileLocked<T>(_ body: () throws -> T) rethrows -> T {
        _condition.lock()
        defer { _condition.unlock() }
        return try body()
    }
}
