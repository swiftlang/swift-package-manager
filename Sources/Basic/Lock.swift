/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import SPMLibc

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

/// Provides functionality to aquire an exclusive lock on a file via POSIX's flock() method.
/// It can be used for things like serializing concurrent mutations on a shared resource
/// by mutiple instances of a process. The `FileLock` is not thread-safe.
public final class FileLock {
    private typealias FileDescriptor = CInt

    /// File descriptor to the lock file.
  #if os(Windows)
    private var handle: HANDLE?
  #else
    private var fileDescriptor: FileDescriptor?
  #endif

    /// Path to the lock file.
    public let path: AbsolutePath

    /// Create an instance of process lock with a name and the path where
    /// the lock file can be created.
    ///
    /// Note: The cache path should be a valid directory.
    public init(name: String, in directory: AbsolutePath) {
        self.path = directory.appending(component: name)
    }

    /// Attempts to acquire a lock and immediately returns a Boolean value
    /// that indicates whether the attempt was successful.
    ///
    /// - Returns: `true` if the lock was acquired, otherwise `false`.
    public func `try`() -> Bool {
        // Open the lock file.
        if self.fileDescriptor == nil, let fileDescriptor = try? openFile(at: path) {
            self.fileDescriptor = fileDescriptor
        }

        guard let fileDescriptor = self.fileDescriptor else { return false }

        // Aquire lock on the file.
        while flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            switch errno {
            case EWOULDBLOCK: // non-blocking lock not available
                return false
            case EINTR: // Retry if interrupted.
                continue
            default:
                return false
            }
        }

        return true
    }

    /// Try to aquire a lock. This method will block until lock the already aquired by other process.
    ///
    /// Note: This method can throw if underlying POSIX methods fail.
    public func lock() throws {
      #if os(Windows)
        if handle == nil {
            let h = lockFile.pathString.withCString(encodedAs: UTF16.self, {
                CreateFileW(
                    $0,
                    UInt32(GENERIC_READ) | UInt32(GENERIC_WRITE),
                    0,
                    nil,
                    DWORD(OPEN_ALWAYS),
                    DWORD(FILE_ATTRIBUTE_NORMAL),
                    nil
                )
            })
            if h == INVALID_HANDLE_VALUE {
                throw FileSystemError(errno: Int32(GetLastError()))
            }
            self.handle = h
        }
        var overlapped = OVERLAPPED()
        overlapped.Offset = 0
        overlapped.OffsetHigh = 0
        overlapped.hEvent = nil
        if FALSE == LockFileEx(handle, DWORD(LOCKFILE_EXCLUSIVE_LOCK), 0, DWORD(INT_MAX), DWORD(INT_MAX), &overlapped) {
            throw ProcessLockError.unableToAquireLock(errno: Int32(GetLastError()))
        }
      #else
        // Open the lock file.
        if fileDescriptor == nil {
            let fd = SPMLibc.open(path.pathString, O_WRONLY | O_CREAT | O_CLOEXEC, 0o666)
            if fd == -1 {
                throw FileSystemError(errno: errno)
            }
            self.fileDescriptor = fd
        }

        // Aquire lock on the file.
        while true {
            if flock(fileDescriptor!, LOCK_EX) == 0 {
                break
            }
            // Retry if interrupted.
            if errno == EINTR {
                continue
            }
            throw ProcessLockError.unableToAquireLock(errno: errno)
        }
      #endif
    }

    /// Unlock the held lock.
    public func unlock() {
      #if os(Windows)
        var overlapped = OVERLAPPED()
        overlapped.Offset = 0
        overlapped.OffsetHigh = 0
        overlapped.hEvent = nil
        UnlockFileEx(handle, 0, DWORD(INT_MAX), DWORD(INT_MAX), &overlapped)
      #else
        guard let fd = fileDescriptor else { return }
        flock(fd, LOCK_UN)
      #endif
    }

    deinit {
      #if os(Windows)
        guard let handle = handle else { return }
        CloseHandle(handle)
      #else
        guard let fd = fileDescriptor else { return }
        close(fd)
      #endif
    }

    /// Execute the given block while holding the lock.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try self.lock()
        defer { self.unlock() }
        return try body()
    }

    private func openFile(at path: AbsolutePath) throws -> FileDescriptor {
        // Open the lock file.
        let fd = SPMLibc.open(path.pathString, O_WRONLY | O_CREAT | O_CLOEXEC, 0o666)
        if fd == -1 {
            throw FileSystemError(errno: errno)
        }
        return fd
    }
}
