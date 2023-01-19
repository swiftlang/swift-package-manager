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
import protocol TSCBasic.FileSystem
import protocol TSCBasic.WritableByteStream
import struct Foundation.Data
import struct Foundation.UUID
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.FileInfo
import struct TSCBasic.FileSystemError

/// Abstracted access to file system operations.
///
/// This actor is used to allow most of the codebase to interact with an
/// asynchronous filesystem interface, while still allowing clients to transparently
/// substitute a virtual file system or redirect file system operations.
public actor AsyncFileSystem: Actor {
    /// Underlying synchronous implementation that conforms to ``FileSystem`` protocol.
    private let implementation: FileSystem

    /// Initialize a new instance of the actor.
    /// - Parameter implementation: an underlying synchronous filesystem.
    public init(_ implementationInitializer: @Sendable () -> FileSystem) {
        self.implementation = implementationInitializer()
    }

    /// Check whether the given path exists and is accessible.
    func exists(_ path: AbsolutePath, followSymlink: Bool = true) -> Bool {
        implementation.exists(path, followSymlink: followSymlink)
    }

    /// Check whether the given path is accessible and a directory.
    func isDirectory(_ path: AbsolutePath) -> Bool {
        implementation.isDirectory(path)
    }

    /// Check whether the given path is accessible and a file.
    func isFile(_ path: AbsolutePath) -> Bool {
        implementation.isFile(path)
    }

    /// Check whether the given path is an accessible and executable file.
    func isExecutableFile(_ path: AbsolutePath) -> Bool {
        implementation.isExecutableFile(path)
    }

    /// Check whether the given path is accessible and is a symbolic link.
    func isSymlink(_ path: AbsolutePath) -> Bool {
        implementation.isSymlink(path)
    }

    /// Check whether the given path is accessible and readable.
    func isReadable(_ path: AbsolutePath) -> Bool {
        implementation.isReadable(path)
    }

    /// Check whether the given path is accessible and writable.
    func isWritable(_ path: AbsolutePath) -> Bool {
        implementation.isWritable(path)
    }

    // FIXME: Actual file system interfaces will allow more efficient access to
    // more data than just the name here.
    //
    /// Get the contents of the given directory, in an undefined order.
    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        try implementation.getDirectoryContents(path)
    }

    /// Get the current working directory (similar to `getcwd(3)`), which can be
    /// different for different (virtualized) implementations of a FileSystem.
    /// The current working directory can be empty if e.g. the directory became
    /// unavailable while the current process was still working in it.
    /// This follows the POSIX `getcwd(3)` semantics.
    var currentWorkingDirectory: AbsolutePath? {
        implementation.currentWorkingDirectory
    }

    /// Change the current working directory.
    /// - Parameters:
    ///   - path: The path to the directory to change the current working directory to.
    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        try implementation.changeCurrentWorkingDirectory(to: path)
    }

    /// Get the home directory of current user
    var homeDirectory: AbsolutePath {
        get throws {
            try implementation.homeDirectory
        }
    }

    /// Get the caches directory of current user
    var cachesDirectory: AbsolutePath? {
        implementation.cachesDirectory
    }

    /// Get the temp directory
    var tempDirectory: AbsolutePath {
        get throws {
            try implementation.tempDirectory
        }
    }

    /// Create the given directory.
    func createDirectory(_ path: AbsolutePath) throws {
        try implementation.createDirectory(path)
    }

    /// Create the given directory.
    ///
    /// - recursive: If true, create missing parent directories if possible.
    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        try implementation.createDirectory(path, recursive: recursive)
    }

    /// Creates a symbolic link of the source path at the target path
    /// - Parameters:
    ///   - path: The path at which to create the link.
    ///   - destination: The path to which the link points to.
    ///   - isRelative: If `true`, the symlink contents will be a relative path, otherwise it will be absolute.
    func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, isRelative: Bool) throws {
        try implementation.createSymbolicLink(path, pointingAt: destination, relative: isRelative)
    }

    // FIXME: This is obviously not a very efficient or flexible API.
    //
    /// Get the contents of a file.
    ///
    /// - Returns: The file contents as bytes, or nil if missing.
    func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        try implementation.readFileContents(path)
    }

    // FIXME: This is obviously not a very efficient or flexible API.
    //
    /// Write the contents of a file.
    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        try implementation.writeFileContents(path, bytes: bytes)
    }

    // FIXME: This is obviously not a very efficient or flexible API.
    //
    /// Write the contents of a file.
    func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        try implementation.writeFileContents(path, bytes: bytes, atomically: atomically)
    }

    /// Recursively deletes the file system entity at `path`.
    ///
    /// If there is no file system entity at `path`, this function does nothing (in particular, this is not considered
    /// to be an error).
    func removeFileTree(_ path: AbsolutePath) throws {
        try implementation.removeFileTree(path)
    }

    /// Change file mode.
    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option> = .init()) throws {
        try implementation.chmod(mode, path: path, options: options)
    }

    /// Returns the file info of the given path.
    ///
    /// The method throws if the underlying stat call fails.
    func getFileInfo(_ path: AbsolutePath) throws -> FileInfo {
        try implementation.getFileInfo(path)
    }

    /// Copy a file or directory.
    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try implementation.copy(from: sourcePath, to: destinationPath)
    }

    /// Move a file or directory.
    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try implementation.move(from: sourcePath, to: destinationPath)
    }

    /// Execute the given block while holding the lock.
    func withLock<T>(on path: AbsolutePath, type: FileLock.LockType, _ body: () throws -> T) throws -> T {
        try implementation.withLock(on: path, type: type, body)
    }
}

/// Convenience implementations
public extension AsyncFileSystem {
    /// Write to a file from a stream producer.
    func writeFileContents(_ path: AbsolutePath, body: (WritableByteStream) -> Void) throws {
        let contents = BufferedOutputByteStream()
        body(contents)
        try createDirectory(path.parentDirectory, recursive: true)
        try writeFileContents(path, bytes: contents.bytes)
    }
}

// MARK: - AsyncUtilities

extension AsyncFileSystem {
    public func readFileContents(_ path: AbsolutePath) throws -> Data {
        return try Data(self.readFileContents(path).contents)
    }

    public func readFileContents(_ path: AbsolutePath) throws -> String {
        return try String(decoding: self.readFileContents(path), as: UTF8.self)
    }

    public func writeFileContents(_ path: AbsolutePath, data: Data) throws {
        return try self.writeFileContents(path, bytes: .init(data))
    }

    public func writeFileContents(_ path: AbsolutePath, string: String) throws {
        return try self.writeFileContents(path, bytes: .init(encodingAsUTF8: string))
    }

    public func writeFileContents(_ path: AbsolutePath, provider: () -> String) throws {
        return try self.writeFileContents(path, string: provider())
    }
}

    func withLock<T>(on path: AbsolutePath, type: FileLock.LockType, _ body: () throws -> T) throws -> T {
        throw FileSystemError(.unsupported, path)
extension AsyncFileSystem {
    public func forceCreateDirectory(at path: AbsolutePath) throws {
        try self.createDirectory(path.parentDirectory, recursive: true)
        if self.exists(path) {
            try self.removeFileTree(path)
        }
        try self.createDirectory(path, recursive: true)
    }
}

extension AsyncFileSystem {
    public func stripFirstLevel(of path: AbsolutePath) throws {
        let topLevelDirectories = try self.getDirectoryContents(path)
            .map{ path.appending(component: $0) }
            .filter{ self.isDirectory($0) }

        guard topLevelDirectories.count == 1, let rootDirectory = topLevelDirectories.first else {
            throw StringError("stripFirstLevel requires single top level directory")
        }

        let tempDirectory = path.parentDirectory.appending(component: UUID().uuidString)
        try self.move(from: rootDirectory, to: tempDirectory)

        let rootContents = try self.getDirectoryContents(tempDirectory)
        for entry in rootContents {
            try self.move(from: tempDirectory.appending(component: entry), to: path.appending(component: entry))
        }

        try self.removeFileTree(tempDirectory)
    }
}

#endif // swift(>=5.5.2)
