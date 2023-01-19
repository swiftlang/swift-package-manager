/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

#if swift(>=5.5.2)
import _Concurrency

import class TSCBasic.BufferedOutputByteStream
import class TSCBasic.FileLock
import enum TSCBasic.FileMode
import protocol TSCBasic.WritableByteStream
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.FileInfo
import struct TSCBasic.FileSystemError

/// Abstracted access to file system operations.
///
/// This protocol is used to allow most of the codebase to interact with a
/// natural filesystem interface, while still allowing clients to transparently
/// substitute a virtual file system or redirect file system operations.
public protocol AsyncFileSystem: Actor {
    /// Check whether the given path exists and is accessible.
    func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool

    /// Check whether the given path is accessible and a directory.
    func isDirectory(_ path: AbsolutePath) -> Bool

    /// Check whether the given path is accessible and a file.
    func isFile(_ path: AbsolutePath) -> Bool

    /// Check whether the given path is an accessible and executable file.
    func isExecutableFile(_ path: AbsolutePath) -> Bool

    /// Check whether the given path is accessible and is a symbolic link.
    func isSymlink(_ path: AbsolutePath) -> Bool

    /// Check whether the given path is accessible and readable.
    func isReadable(_ path: AbsolutePath) -> Bool

    /// Check whether the given path is accessible and writable.
    func isWritable(_ path: AbsolutePath) -> Bool

    // FIXME: Actual file system interfaces will allow more efficient access to
    // more data than just the name here.
    //
    /// Get the contents of the given directory, in an undefined order.
    func getDirectoryContents(_ path: AbsolutePath) throws -> [String]

    /// Get the current working directory (similar to `getcwd(3)`), which can be
    /// different for different (virtualized) implementations of a FileSystem.
    /// The current working directory can be empty if e.g. the directory became
    /// unavailable while the current process was still working in it.
    /// This follows the POSIX `getcwd(3)` semantics.
    var currentWorkingDirectory: AbsolutePath? { get }

    /// Change the current working directory.
    /// - Parameters:
    ///   - path: The path to the directory to change the current working directory to.
    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws

    /// Get the home directory of current user
    var homeDirectory: AbsolutePath { get throws }

    /// Get the caches directory of current user
    var cachesDirectory: AbsolutePath? { get }

    /// Get the temp directory
    var tempDirectory: AbsolutePath { get throws }

    /// Create the given directory.
    func createDirectory(_ path: AbsolutePath) throws

    /// Create the given directory.
    ///
    /// - recursive: If true, create missing parent directories if possible.
    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws

    /// Creates a symbolic link of the source path at the target path
    /// - Parameters:
    ///   - path: The path at which to create the link.
    ///   - destination: The path to which the link points to.
    ///   - relative: If `relative` is true, the symlink contents will be a relative path, otherwise it will be absolute.
    func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws

    // FIXME: This is obviously not a very efficient or flexible API.
    //
    /// Get the contents of a file.
    ///
    /// - Returns: The file contents as bytes, or nil if missing.
    func readFileContents(_ path: AbsolutePath) throws -> ByteString

    // FIXME: This is obviously not a very efficient or flexible API.
    //
    /// Write the contents of a file.
    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws

    // FIXME: This is obviously not a very efficient or flexible API.
    //
    /// Write the contents of a file.
    func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws

    /// Recursively deletes the file system entity at `path`.
    ///
    /// If there is no file system entity at `path`, this function does nothing (in particular, this is not considered
    /// to be an error).
    func removeFileTree(_ path: AbsolutePath) throws

    /// Change file mode.
    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws

    /// Returns the file info of the given path.
    ///
    /// The method throws if the underlying stat call fails.
    func getFileInfo(_ path: AbsolutePath) throws -> FileInfo

    /// Copy a file or directory.
    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws

    /// Move a file or directory.
    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws

    /// Execute the given block while holding the lock.
    func withLock<T>(on path: AbsolutePath, type: FileLock.LockType, _ body: () throws -> T) throws -> T
}

/// Convenience implementations (default arguments aren't permitted in protocol
/// methods).
public extension AsyncFileSystem {
    /// exists override with default value.
    func exists(_ path: AbsolutePath) -> Bool {
        exists(path, followSymlink: true)
    }

    /// Default implementation of createDirectory(_:)
    func createDirectory(_ path: AbsolutePath) throws {
        try createDirectory(path, recursive: false)
    }

    // Change file mode.
    func chmod(_ mode: FileMode, path: AbsolutePath) throws {
        try chmod(mode, path: path, options: [])
    }

    // Unless the file system type provides an override for this method, throw
    // if `atomically` is `true`, otherwise fall back to whatever implementation already exists.
    func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        guard !atomically else {
            throw FileSystemError(.unsupported, path)
        }
        try writeFileContents(path, bytes: bytes)
    }

    /// Write to a file from a stream producer.
    func writeFileContents(_ path: AbsolutePath, body: (WritableByteStream) -> Void) throws {
        let contents = BufferedOutputByteStream()
        body(contents)
        try createDirectory(path.parentDirectory, recursive: true)
        try writeFileContents(path, bytes: contents.bytes)
    }

    func getFileInfo(_ path: AbsolutePath) throws -> FileInfo {
        throw FileSystemError(.unsupported, path)
    }

    func withLock<T>(on path: AbsolutePath, type: FileLock.LockType, _ body: () throws -> T) throws -> T {
        throw FileSystemError(.unsupported, path)
    }
}
#endif
