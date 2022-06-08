/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

/// A simple lock wrapper.
public struct Lock {
    private let _lock = NSLock()
    
    /// Create a new lock.
    public init() {
    }
    
    func lock() {
        _lock.lock()
    }
    
    func unlock() {
        _lock.unlock()
    }
    
    /// Execute the given block while holding the lock.
    public func withLock<T> (_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
