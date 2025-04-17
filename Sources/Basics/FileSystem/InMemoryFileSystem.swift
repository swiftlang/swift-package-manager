/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.NSLock
import class Dispatch.DispatchQueue
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import class TSCBasic.FileLock
import enum TSCBasic.FileMode
import struct TSCBasic.FileSystemError

/// Concrete FileSystem implementation which simulates an empty disk.
public final class InMemoryFileSystem: FileSystem {
    /// Private internal representation of a file system node.
    /// Not thread-safe.
    private class Node {
        /// The actual node data.
        let contents: NodeContents
        
        /// Whether the node has executable bit enabled.
        var isExecutable: Bool

        init(_ contents: NodeContents, isExecutable: Bool = false) {
            self.contents = contents
            self.isExecutable = isExecutable
        }

        /// Creates deep copy of the object.
        func copy() -> Node {
            return Node(contents.copy())
        }
    }

    /// Private internal representation the contents of a file system node.
    /// Not thread-safe.
    private enum NodeContents {
        case file(ByteString)
        case directory(DirectoryContents)
        case symlink(String)

        /// Creates deep copy of the object.
        func copy() -> NodeContents {
            switch self {
            case .file(let bytes):
                return .file(bytes)
            case .directory(let contents):
                return .directory(contents.copy())
            case .symlink(let path):
                return .symlink(path)
            }
        }
    }

    /// Private internal representation the contents of a directory.
    /// Not thread-safe.
    private final class DirectoryContents {
        var entries: [String: Node]

        init(entries: [String: Node] = [:]) {
            self.entries = entries
        }

        /// Creates deep copy of the object.
        func copy() -> DirectoryContents {
            let contents = DirectoryContents()
            for (key, node) in entries {
                contents.entries[key] = node.copy()
            }
            return contents
        }
    }

    /// The root node of the filesystem.
    private var root: Node

    /// Protects `root` and everything underneath it.
    /// FIXME: Using a single lock for this is a performance problem, but in
    /// reality, the only practical use for InMemoryFileSystem is for unit
    /// tests.
    private let lock = NSLock()
    /// A map that keeps weak references to all locked files.
    private var lockFiles = Dictionary<TSCBasic.AbsolutePath, WeakReference<DispatchQueue>>()
    /// Used to access lockFiles in a thread safe manner.
    private let lockFilesLock = NSLock()

    /// Exclusive file system lock vended to clients through `withLock()`.
    /// Used to ensure that DispatchQueues are released when they are no longer in use.
    private struct WeakReference<Value: AnyObject> {
        weak var reference: Value?

        init(_ value: Value?) {
            self.reference = value
        }
    }

    public init() {
        root = Node(.directory(DirectoryContents()))
    }

    /// Creates deep copy of the object.
    public func copy() -> InMemoryFileSystem {
        return lock.withLock {
            let fs = InMemoryFileSystem()
            fs.root = root.copy()
            return fs
        }
    }

    /// Private function to look up the node corresponding to a path.
    /// Not thread-safe.
    private func getNode(_ path: TSCBasic.AbsolutePath, followSymlink: Bool = true) throws -> Node? {
        func getNodeInternal(_ path: TSCBasic.AbsolutePath) throws -> Node? {
            // If this is the root node, return it.
            if path.isRoot {
                return root
            }

            // Otherwise, get the parent node.
            guard let parent = try getNodeInternal(path.parentDirectory) else {
                return nil
            }

            // If we didn't find a directory, this is an error.
            guard case .directory(let contents) = parent.contents else {
                throw FileSystemError(.notDirectory, path.parentDirectory)
            }

            // Return the directory entry.
            let node = contents.entries[path.basename]

            switch node?.contents {
            case .directory, .file:
                return node
            case .symlink(let destination):
                let destination = try TSCBasic.AbsolutePath(validating: destination, relativeTo: path.parentDirectory)
                return followSymlink ? try getNodeInternal(destination) : node
            case .none:
                return nil
            }
        }

        // Get the node that corresponds to the path.
        return try getNodeInternal(path)
    }

    // MARK: FileSystem Implementation

    public func exists(_ path: TSCBasic.AbsolutePath, followSymlink: Bool) -> Bool {
        return lock.withLock {
            do {
                switch try getNode(path, followSymlink: followSymlink)?.contents {
                case .file, .directory, .symlink: return true
                case .none: return false
                }
            } catch {
                return false
            }
        }
    }

    public func isDirectory(_ path: TSCBasic.AbsolutePath) -> Bool {
        return lock.withLock {
            do {
                if case .directory? = try getNode(path)?.contents {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
    }

    public func isFile(_ path: TSCBasic.AbsolutePath) -> Bool {
        return lock.withLock {
            do {
                if case .file? = try getNode(path)?.contents {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
    }

    public func isSymlink(_ path: TSCBasic.AbsolutePath) -> Bool {
        return lock.withLock {
            do {
                if case .symlink? = try getNode(path, followSymlink: false)?.contents {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
    }

    public func isReadable(_ path: TSCBasic.AbsolutePath) -> Bool {
        self.exists(path)
    }

    public func isWritable(_ path: TSCBasic.AbsolutePath) -> Bool {
        self.exists(path)
    }

    public func isExecutableFile(_ path: TSCBasic.AbsolutePath) -> Bool {
        (try? self.getNode(path)?.isExecutable) ?? false
    }

    public func updatePermissions(_ path: AbsolutePath, isExecutable: Bool) throws {
        try lock.withLock {
            guard let node = try self.getNode(path.underlying, followSymlink: true) else {
                throw FileSystemError(.noEntry, path)
            }
            node.isExecutable = isExecutable
        }
    }

    /// Virtualized current working directory.
    public var currentWorkingDirectory: TSCBasic.AbsolutePath? {
        return try? .init(validating: "/")
    }

    public func changeCurrentWorkingDirectory(to path: TSCBasic.AbsolutePath) throws {
        throw FileSystemError(.unsupported, path)
    }

    public var homeDirectory: TSCBasic.AbsolutePath {
        get throws {
            // FIXME: Maybe we should allow setting this when creating the fs.
            return try .init(validating: "/home/user")
        }
    }

    public var cachesDirectory: TSCBasic.AbsolutePath? {
        return try? self.homeDirectory.appending(component: "caches")
    }

    public var tempDirectory: TSCBasic.AbsolutePath {
        get throws {
            return try .init(validating: "/tmp")
        }
    }

    public func getDirectoryContents(_ path: TSCBasic.AbsolutePath) throws -> [String] {
        return try lock.withLock {
            guard let node = try getNode(path) else {
                throw FileSystemError(.noEntry, path)
            }
            guard case .directory(let contents) = node.contents else {
                throw FileSystemError(.notDirectory, path)
            }

            // FIXME: Perhaps we should change the protocol to allow lazy behavior.
            return [String](contents.entries.keys)
        }
    }

    /// Not thread-safe.
    private func _createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws {
        // Ignore if client passes root.
        guard !path.isRoot else {
            return
        }
        // Get the parent directory node.
        let parentPath = path.parentDirectory
        guard let parent = try getNode(parentPath) else {
            // If the parent doesn't exist, and we are recursive, then attempt
            // to create the parent and retry.
            if recursive && path != parentPath {
                // Attempt to create the parent.
                try _createDirectory(parentPath, recursive: true)

                // Re-attempt creation, non-recursively.
                return try _createDirectory(path, recursive: false)
            } else {
                // Otherwise, we failed.
                throw FileSystemError(.noEntry, parentPath)
            }
        }

        // Check that the parent is a directory.
        guard case .directory(let contents) = parent.contents else {
            // The parent isn't a directory, this is an error.
            throw FileSystemError(.notDirectory, parentPath)
        }

        // Check if the node already exists.
        if let node = contents.entries[path.basename] {
            // Verify it is a directory.
            guard case .directory = node.contents else {
                // The path itself isn't a directory, this is an error.
                throw FileSystemError(.notDirectory, path)
            }

            // We are done.
            return
        }

        // Otherwise, the node does not exist, create it.
        contents.entries[path.basename] = Node(.directory(DirectoryContents()))
    }

    public func createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws {
        return try lock.withLock {
            try _createDirectory(path, recursive: recursive)
        }
    }

    public func createSymbolicLink(
        _ path: TSCBasic.AbsolutePath,
        pointingAt destination: TSCBasic.AbsolutePath,
        relative: Bool
    ) throws {
        return try lock.withLock {
            // Create directory to destination parent.
            guard let destinationParent = try getNode(path.parentDirectory) else {
                throw FileSystemError(.noEntry, path.parentDirectory)
            }

            // Check that the parent is a directory.
            guard case .directory(let contents) = destinationParent.contents else {
                throw FileSystemError(.notDirectory, path.parentDirectory)
            }

            guard contents.entries[path.basename] == nil else {
                throw FileSystemError(.alreadyExistsAtDestination, path)
            }

            let destination = relative ? destination.relative(to: path.parentDirectory).pathString : destination.pathString

            contents.entries[path.basename] = Node(.symlink(destination))
        }
    }

    public func readFileContents(_ path: TSCBasic.AbsolutePath) throws -> ByteString {
        return try lock.withLock {
            // Get the node.
            guard let node = try getNode(path) else {
                throw FileSystemError(.noEntry, path)
            }

            // Check that the node is a file.
            guard case .file(let contents) = node.contents else {
                // The path is a directory, this is an error.
                throw FileSystemError(.isDirectory, path)
            }

            // Return the file contents.
            return contents
        }
    }

    public func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: ByteString) throws {
        return try lock.withLock {
            // It is an error if this is the root node.
            let parentPath = path.parentDirectory
            guard path != parentPath else {
                throw FileSystemError(.isDirectory, path)
            }

            // Get the parent node.
            guard let parent = try getNode(parentPath) else {
                throw FileSystemError(.noEntry, parentPath)
            }

            // Check that the parent is a directory.
            guard case .directory(let contents) = parent.contents else {
                // The parent isn't a directory, this is an error.
                throw FileSystemError(.notDirectory, parentPath)
            }

            // Check if the node exists.
            if let node = contents.entries[path.basename] {
                // Verify it is a file.
                guard case .file = node.contents else {
                    // The path is a directory, this is an error.
                    throw FileSystemError(.isDirectory, path)
                }
            }

            // Write the file.
            contents.entries[path.basename] = Node(.file(bytes))
        }
    }

    public func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        // In memory file system's writeFileContents is already atomic, so ignore the parameter here
        // and just call the base implementation.
        try writeFileContents(path, bytes: bytes)
    }

    public func removeFileTree(_ path: TSCBasic.AbsolutePath) throws {
        return lock.withLock {
            // Ignore root and get the parent node's content if its a directory.
            guard !path.isRoot,
                  let parent = try? getNode(path.parentDirectory),
                  case .directory(let contents) = parent.contents else {
                      return
                  }
            // Set it to nil to release the contents.
            contents.entries[path.basename] = nil
        }
    }

    public func chmod(_ mode: FileMode, path: TSCBasic.AbsolutePath, options: Set<FileMode.Option>) throws {
        // FIXME: We don't have these semantics in InMemoryFileSystem.
    }

    /// Private implementation of core copying function.
    /// Not thread-safe.
    private func _copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        // Get the source node.
        guard let source = try getNode(sourcePath) else {
            throw FileSystemError(.noEntry, sourcePath)
        }

        // Create directory to destination parent.
        guard let destinationParent = try getNode(destinationPath.parentDirectory) else {
            throw FileSystemError(.noEntry, destinationPath.parentDirectory)
        }

        // Check that the parent is a directory.
        guard case .directory(let contents) = destinationParent.contents else {
            throw FileSystemError(.notDirectory, destinationPath.parentDirectory)
        }

        guard contents.entries[destinationPath.basename] == nil else {
            throw FileSystemError(.alreadyExistsAtDestination, destinationPath)
        }

        contents.entries[destinationPath.basename] = source
    }

    public func copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        return try lock.withLock {
            try _copy(from: sourcePath, to: destinationPath)
        }
    }

    public func move(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        return try lock.withLock {
            // Get the source parent node.
            guard let sourceParent = try getNode(sourcePath.parentDirectory) else {
                throw FileSystemError(.noEntry, sourcePath.parentDirectory)
            }

            // Check that the parent is a directory.
            guard case .directory(let contents) = sourceParent.contents else {
                throw FileSystemError(.notDirectory, sourcePath.parentDirectory)
            }

            try _copy(from: sourcePath, to: destinationPath)

            contents.entries[sourcePath.basename] = nil
        }
    }

    public func withLock<T>(
        on path: TSCBasic.AbsolutePath,
        type: FileLock.LockType = .exclusive,
        _ body: () throws -> T
    ) throws -> T {
        let resolvedPath: TSCBasic.AbsolutePath = try lock.withLock {
            if case let .symlink(destination) = try getNode(path)?.contents {
                return try .init(validating: destination, relativeTo: path.parentDirectory)
            } else {
                return path
            }
        }

        let fileQueue: DispatchQueue = lockFilesLock.withLock {
            if let queueReference = lockFiles[resolvedPath], let queue = queueReference.reference {
                return queue
            } else {
                let queue = DispatchQueue(label: "org.swift.swiftpm.in-memory-file-system.file-queue", attributes: .concurrent)
                lockFiles[resolvedPath] = WeakReference(queue)
                return queue
            }
        }

        return try fileQueue.sync(flags: type == .exclusive ? .barrier : .init() , execute: body)
    }
    
    public func withLock<T>(on path: TSCBasic.AbsolutePath, type: FileLock.LockType, blocking: Bool, _ body: () throws -> T) throws -> T {
        try self.withLock(on: path, type: type, body)
    }
}

// Internal state of `InMemoryFileSystem` is protected with a lock in all of its `public` methods.
extension InMemoryFileSystem: @unchecked Sendable {}
