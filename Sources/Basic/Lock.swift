/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch
import Foundation
import libc

/// A simple lock wrapper.
public struct Lock {
    private var _lock = NSLock()

    /// Create a new lock.
    public init() {
    }

    /// Execute the given block while holding the lock.
    public mutating func withLock<T> (_ body: () throws -> T) rethrows -> T {
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

    /// Indicates if the timer was fired.
    private var timerTicked = false

    /// Create an instance of process lock with a name and the path where
    /// the lock file can be created.
    ///
    /// Note: The cache path should be a valid directory.
    public init(name: String, cachePath: AbsolutePath) {
        self.name = name
        self.cachePath = cachePath
    }

    /// Registers signal handler for SIGUSR1 and raises the signal
    /// after the given number of seconds.
    private func setupTimeout(seconds: Double) {
        // Reset the timer indicator.
        timerTicked = false
        // Register signal handler to avoid process termination.
        SignalManager.shared.register(.usr1) {}
        // Raise the signal when we reach timeout.
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            // Tick the timer.
            self.timerTicked = true
            // Raise the signal.
            SignalManager.shared.raise(.usr1)
        }
    }

    /// Try to aquire a lock. This method will block if a lock is already aquired by other process.
    ///
    /// Note: This method can throw if underlying POSIX methods fail.
    ///
    /// - Parameters:
    ///   - timeout: If provided, the method will return in case the lock is not aquired within the timeout value.
    /// - Returns: True if lock was aquired, false otherwise.
    @discardableResult
    public func lock(timeout seconds: Double? = nil) throws -> Bool {
        if let seconds = seconds {
            setupTimeout(seconds: seconds)
        }
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
            if errno == EINTR {
                // We consider a timeout occurred if a timeout was provided and timer had ticked when we were interrupted.
                if seconds != nil && timerTicked { 
                    // If there is a timeout return false to indicate that
                    // we couldn't aquire a lock.
                    return false
                }
                // Otherwise, retry.
                continue
            }
            throw ProcessLockError.unableToAquireLock(errno: errno)
        }
        return true
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
