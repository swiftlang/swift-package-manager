//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import _Concurrency
@preconcurrency package import struct SystemPackage.Errno
@preconcurrency package import struct SystemPackage.FilePath

/// An abstract file system protocol with first-class support for Swift Concurrency.
package protocol AsyncFileSystem: Actor {
    /// Whether a file exists on the file system.
    /// - Parameter path: Absolute path to the file to check.
    /// - Returns: `true` if the file exists, `false` otherwise.
    func exists(_ path: FilePath) async -> Bool

    /// Temporarily opens a read-only file within a scope defined by a given closure.
    /// - Parameters:
    ///   - path: Absolute path to a readable file on this file system.
    ///   - body: Closure that has temporary read-only access to the open file. The underlying file handle is closed
    ///   when this closure returns, thus in the current absence of `~Escapable` types in Swift 6.0, users should take
    ///   care not to allow this handle to escape the closure.
    /// - Returns: Result of the `body` closure.
    func withOpenReadableFile<T>(
        _ path: FilePath,
        _ body: @Sendable (_ fileHandle: OpenReadableFile) async throws -> T
    ) async throws -> T

    /// Temporarily opens a write-only file within a scope defined by a given closure.
    /// - Parameters:
    ///   - path: Absolute path to a writable file on this file system.
    ///   - body: Closure that has temporary write-only access to the open file. The underlying file handle is closed
    ///   when this closure returns, thus in the current absence of `~Escapable` types in Swift 6.0, users should take
    ///   care not to allow this handle to escape the closure.
    /// - Returns: Result of the `body` closure.
    func withOpenWritableFile<T>(
        _ path: FilePath,
        _ body: @Sendable (_ fileHandle: OpenWritableFile) async throws -> T
    ) async throws -> T
}

/// Errors that can be thrown by the ``AsyncFileSystem`` type.
package enum AsyncFileSystemError: Error {
    /// A file with the associated ``FilePath`` value does not exist.
    case fileDoesNotExist(FilePath)

    /// A wrapper for the underlying `SystemPackage` error types that attaches a ``FilePath`` value to it.
    case systemError(FilePath, Errno)
}

extension Error {
    /// Makes a system error value more actionable and readable by the end user.
    /// - Parameter path: absolute path to the file, operations on which caused this error.
    /// - Returns: An ``AsyncFileSystemError`` value augmented by the given file path.
    func attach(_ path: FilePath) -> any Error {
        if let error = self as? Errno {
            return AsyncFileSystemError.systemError(path, error)
        } else {
            return self
        }
    }
}

extension AsyncFileSystem {
    package func write(_ path: FilePath, bytes: some Collection<UInt8> & Sendable) async throws {
        try await self.withOpenWritableFile(path) { fileHandle in
            try await fileHandle.write(bytes)
        }
    }
}
