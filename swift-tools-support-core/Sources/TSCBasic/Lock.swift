/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCLibc

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

enum ProcessLockError: Swift.Error {
    case unableToAquireLock(errno: Int32)
}

/// Provides functionality to aquire a lock on a file via POSIX's flock() method.
/// It can be used for things like serializing concurrent mutations on a shared resource
/// by mutiple instances of a process. The `FileLock` is not thread-safe.
public final class FileLock {

    public enum LockType {
        case exclusive
        case shared
    }

    /// File descriptor to the lock file.
  #if os(Windows)
    private var handle: HANDLE?
  #else
    private var fileDescriptor: CInt?
  #endif

    /// Path to the lock file.
    private let lockFile: AbsolutePath

    /// Create an instance of process lock with a name and the path where
    /// the lock file can be created.
    ///
    /// Note: The cache path should be a valid directory.
    public init(name: String, cachePath: AbsolutePath) {
        self.lockFile = cachePath.appending(component: name + ".lock")
    }

    /// Try to aquire a lock. This method will block until lock the already aquired by other process.
    ///
    /// Note: This method can throw if underlying POSIX methods fail.
    public func lock(type: LockType = .exclusive) throws {
      #if os(Windows)
        if handle == nil {
            let h: HANDLE = lockFile.pathString.withCString(encodedAs: UTF16.self, {
                CreateFileW(
                    $0,
                    UInt32(GENERIC_READ) | UInt32(GENERIC_WRITE),
                    UInt32(FILE_SHARE_READ) | UInt32(FILE_SHARE_WRITE),
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
        switch type {
        case .exclusive:
            if !LockFileEx(handle, DWORD(LOCKFILE_EXCLUSIVE_LOCK), 0,
                           DWORD(INT_MAX), DWORD(INT_MAX), &overlapped) {
                throw ProcessLockError.unableToAquireLock(errno: Int32(GetLastError()))
            }
        case .shared:
            if !LockFileEx(handle, 0, 0,
                           DWORD(INT_MAX), DWORD(INT_MAX), &overlapped) {
                throw ProcessLockError.unableToAquireLock(errno: Int32(GetLastError()))
            }
        }
      #else
        // Open the lock file.
        if fileDescriptor == nil {
            let fd = TSCLibc.open(lockFile.pathString, O_WRONLY | O_CREAT | O_CLOEXEC, 0o666)
            if fd == -1 {
                throw FileSystemError(errno: errno)
            }
            self.fileDescriptor = fd
        }
        // Aquire lock on the file.
        while true {
            if type == .exclusive && flock(fileDescriptor!, LOCK_EX) == 0 {
                break
            } else if type == .shared && flock(fileDescriptor!, LOCK_SH) == 0 {
                break
            }
            // Retry if interrupted.
            if errno == EINTR { continue }
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
    public func withLock<T>(type: LockType = .exclusive, _ body: () throws -> T) throws -> T {
        try lock(type: type)
        defer { unlock() }
        return try body()
    }
}
