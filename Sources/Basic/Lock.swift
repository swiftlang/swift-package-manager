/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import libc

/// A simple lock wrapper.
public struct Lock {
    private let _lock = NSLock()

    /// Create a new lock.
    public init() {
    }

    /// Execute the given block while holding the lock.
    public func withLock<T> (_ body: () throws -> T) rethrows -> T {
        _lock.lock()
        defer { _lock.unlock() }
        return try body()
    }
}

enum ProcessLockError: Swift.Error {
    case unableToAquireLock(errno: Int32)
}

/// Provides functionality to aquire a lock on a file via POSIX's flock() method.
/// It can be used for things like serializing concurrent mutations on a shared resource
/// by mutiple instances of a process.
public final class FileLock {
    /// The name of the lock, used in filename of the lock file.
    let name: String

    /// The directory where the lock file should be created.
    let cachePath: AbsolutePath

    /// File descriptor to the lock file.
    private var fd: Int32?

    /// Path to the lock file.
    private var lockFile: AbsolutePath {
        return cachePath.appending(component: name + ".lock")
    }

    /// Create an instance of process lock with a name and the path where
    /// the lock file can be created.
    ///
    /// Note: The cache path should be a valid directory.
    public init(name: String, cachePath: AbsolutePath) {
        self.name = name
        self.cachePath = cachePath
    }

    /// Try to aquire a lock. This method will block until lock the already aquired by other process.
    ///
    /// Note: This method can throw if underlying POSIX methods fail.
    public func lock() throws {
        // Open the lock file.
        let fp = libc.fopen(lockFile.asString, "w")
        if fp == nil {
            throw FileSystemError(errno: errno)
        }
        // Save the fd to close and remove lock later.
        fd = fileno(fp)
        // Aquire lock on the file.
        while true {
            if flock(fd!, LOCK_EX) == 0 {
                break
            }
            // Retry if interrupted.
            if errno == EINTR { continue }
            throw ProcessLockError.unableToAquireLock(errno: errno)
        }
    }

    /// Unlock the held lock.
    public func unlock() {
        guard let fd = fd else { return }
        flock(fd, LOCK_UN)
        close(fd)
        self.fd = nil
    }

    /// Execute the given block while holding the lock.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try lock()
        defer { unlock() }
        return try body()
    }
}
