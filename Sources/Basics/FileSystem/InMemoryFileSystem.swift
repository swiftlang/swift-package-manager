//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Dispatch.DispatchQueue
import Synchronization
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import class TSCBasic.FileLock
import enum TSCBasic.FileMode
import struct TSCBasic.FileSystemError

/// Concrete FileSystem implementation which simulates an empty disk.
public final class InMemoryFileSystem: FileSystem {
    /// Private internal representation of a file system node, and of the tree operations rooted at one.
    ///
    /// Not thread-safe. Callers must hold the state lock, and must not let a `Node` outlive the
    /// `withLock` closure it came from: the compiler does not enforce either rule.
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
        func copy() -> sending Node {
            return Node(contents.copy(), isExecutable: isExecutable)
        }

        /// Looks up the node corresponding to `path`.
        func node(at path: TSCBasic.AbsolutePath, followSymlink: Bool = true) throws -> Node? {
            // If this is the root node, return it.
            if path.isRoot {
                return self
            }

            // Otherwise, get the parent node.
            guard let parent = try self.node(at: path.parentDirectory, followSymlink: followSymlink) else {
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
                return followSymlink ? try self.node(at: destination, followSymlink: followSymlink) : node
            case .none:
                return nil
            }
        }

        /// Creates a directory at `path`.
        func createDirectory(at path: TSCBasic.AbsolutePath, recursive: Bool) throws {
            // Ignore if client passes root.
            guard !path.isRoot else {
                return
            }
            // Get the parent directory node.
            let parentPath = path.parentDirectory
            guard let parent = try self.node(at: parentPath) else {
                // If the parent doesn't exist, and we are recursive, then attempt
                // to create the parent and retry.
                if recursive && path != parentPath {
                    // Attempt to create the parent.
                    try self.createDirectory(at: parentPath, recursive: true)

                    // Re-attempt creation, non-recursively.
                    return try self.createDirectory(at: path, recursive: false)
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

        /// Grafts the node at `sourcePath` onto `destinationPath`.
        ///
        /// The destination shares the source's node rather than deep copying it; see `copy()` for a
        /// deep copy.
        func graft(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
            // Get the source node.
            guard let source = try self.node(at: sourcePath) else {
                throw FileSystemError(.noEntry, sourcePath)
            }

            // Create directory to destination parent.
            guard let destinationParent = try self.node(at: destinationPath.parentDirectory) else {
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
    }

    /// Private internal representation the contents of a file system node.
    /// Not thread-safe.
    private enum NodeContents {
        case file(ByteString)
        case directory(DirectoryContents)
        case symlink(String)

        /// Creates deep copy of the object.
        func copy() -> sending NodeContents {
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
        func copy() -> sending DirectoryContents {
            let contents = DirectoryContents()
            for (key, node) in entries {
                contents.entries[key] = node.copy()
            }
            return contents
        }
    }

    /// The mutable state of the filesystem: the root node and everything underneath it, plus the
    /// virtualized working directory.
    private struct State {
        let root: Node
        var currentWorkingDirectory: TSCBasic.AbsolutePath
    }

    /// FIXME: Using a single lock for this is a performance problem, but in
    /// reality, the only practical use for InMemoryFileSystem is for unit tests.
    private let state: Mutex<State>

    /// A map that keeps weak references to all locked files.
    private let lockFiles = Mutex<[TSCBasic.AbsolutePath: WeakReference<DispatchQueue>]>([:])

    /// Exclusive file system lock vended to clients through `withLock()`.
    /// Used to ensure that DispatchQueues are released when they are no longer in use.
    private struct WeakReference<Value: AnyObject> {
        weak var reference: Value?

        init(_ value: Value?) {
            self.reference = value
        }
    }

    public convenience init() {
        self.init(root: Node(.directory(DirectoryContents())))
    }

    private init(root: sending Node) {
        self.state = Mutex(
            State(root: root, currentWorkingDirectory: try! .init(validating: "/"))
        )
    }

    /// Creates deep copy of the object.
    public func copy() -> InMemoryFileSystem {
        self.state.withLock { state in
            InMemoryFileSystem(root: state.root.copy())
        }
    }

    // MARK: FileSystem Implementation

    public func exists(_ path: TSCBasic.AbsolutePath, followSymlink: Bool) -> Bool {
        return self.state.withLock { state in
            do {
                switch try state.root.node(at: path, followSymlink: followSymlink)?.contents {
                case .file, .directory, .symlink: return true
                case .none: return false
                }
            } catch {
                return false
            }
        }
    }

    public func isDirectory(_ path: TSCBasic.AbsolutePath) -> Bool {
        return self.state.withLock { state in
            do {
                if case .directory? = try state.root.node(at: path)?.contents {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
    }

    public func isFile(_ path: TSCBasic.AbsolutePath) -> Bool {
        return self.state.withLock { state in
            do {
                if case .file? = try state.root.node(at: path)?.contents {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
    }

    public func isSymlink(_ path: TSCBasic.AbsolutePath) -> Bool {
        return self.state.withLock { state in
            do {
                if case .symlink? = try state.root.node(at: path, followSymlink: false)?.contents {
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
        self.state.withLock { state in
            (try? state.root.node(at: path)?.isExecutable) ?? false
        }
    }

    public func updatePermissions(_ path: AbsolutePath, isExecutable: Bool) throws {
        try self.state.withLock { state in
            guard let node = try state.root.node(at: path.underlying, followSymlink: true) else {
                throw FileSystemError(.noEntry, path)
            }
            node.isExecutable = isExecutable
        }
    }

    public var currentWorkingDirectory: TSCBasic.AbsolutePath? {
        self.state.withLock { $0.currentWorkingDirectory }
    }

    public func changeCurrentWorkingDirectory(to path: TSCBasic.AbsolutePath) throws {
        return try self.state.withLock { state in
            // Verify the path exists and is a directory
            guard let node = try state.root.node(at: path) else {
                throw FileSystemError(.noEntry, path)
            }

            guard case .directory = node.contents else {
                throw FileSystemError(.notDirectory, path)
            }
            state.currentWorkingDirectory = path
        }
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
        return try self.state.withLock { state in
            guard let node = try state.root.node(at: path) else {
                throw FileSystemError(.noEntry, path)
            }
            guard case .directory(let contents) = node.contents else {
                throw FileSystemError(.notDirectory, path)
            }

            // FIXME: Perhaps we should change the protocol to allow lazy behavior.
            return [String](contents.entries.keys)
        }
    }

    public func createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws {
        return try self.state.withLock { state in
            try state.root.createDirectory(at: path, recursive: recursive)
        }
    }

    public func createSymbolicLink(
        _ path: TSCBasic.AbsolutePath,
        pointingAt destination: TSCBasic.AbsolutePath,
        relative: Bool
    ) throws {
        return try self.state.withLock { state in
            // Create directory to destination parent.
            guard let destinationParent = try state.root.node(at: path.parentDirectory) else {
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
        return try self.state.withLock { state in
            // Get the node.
            guard let node = try state.root.node(at: path) else {
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
        return try self.state.withLock { state in
            // It is an error if this is the root node.
            let parentPath = path.parentDirectory
            guard path != parentPath else {
                throw FileSystemError(.isDirectory, path)
            }

            // Get the parent node.
            guard let parent = try state.root.node(at: parentPath) else {
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
        return self.state.withLock { state in
            // Ignore root and get the parent node's content if its a directory.
            guard !path.isRoot,
                  let parent = try? state.root.node(at: path.parentDirectory),
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

    public func copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        return try self.state.withLock { state in
            try state.root.graft(from: sourcePath, to: destinationPath)
        }
    }

    public func move(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        return try self.state.withLock { state in
            // Get the source parent node.
            guard let sourceParent = try state.root.node(at: sourcePath.parentDirectory) else {
                throw FileSystemError(.noEntry, sourcePath.parentDirectory)
            }

            // Check that the parent is a directory.
            guard case .directory(let contents) = sourceParent.contents else {
                throw FileSystemError(.notDirectory, sourcePath.parentDirectory)
            }

            try state.root.graft(from: sourcePath, to: destinationPath)

            contents.entries[sourcePath.basename] = nil
        }
    }

    public func withLock<T>(
        on path: TSCBasic.AbsolutePath,
        type: FileLock.LockType = .exclusive,
        _ body: () throws -> T
    ) throws -> T {
        let resolvedPath: TSCBasic.AbsolutePath = try self.state.withLock { state in
            if case let .symlink(destination) = try state.root.node(at: path)?.contents {
                return try .init(validating: destination, relativeTo: path.parentDirectory)
            } else {
                return path
            }
        }

        let fileQueue: DispatchQueue = self.lockFiles.withLock { lockFiles in
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
