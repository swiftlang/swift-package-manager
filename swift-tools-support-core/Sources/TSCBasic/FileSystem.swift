/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCLibc
import Foundation
import Dispatch

public struct FileSystemError: Swift.Error, Equatable {
    public enum Kind: Equatable {
        /// Access to the path is denied.
        ///
        /// This is used when an operation cannot be completed because a component of
        /// the path cannot be accessed.
        ///
        /// Used in situations that correspond to the POSIX EACCES error code.
        case invalidAccess

        /// IO Error encoding
        ///
        /// This is used when an operation cannot be completed due to an otherwise
        /// unspecified IO error.
        case ioError(code: Int32)

        /// Is a directory
        ///
        /// This is used when an operation cannot be completed because a component
        /// of the path which was expected to be a file was not.
        ///
        /// Used in situations that correspond to the POSIX EISDIR error code.
        case isDirectory

        /// No such path exists.
        ///
        /// This is used when a path specified does not exist, but it was expected
        /// to.
        ///
        /// Used in situations that correspond to the POSIX ENOENT error code.
        case noEntry

        /// Not a directory
        ///
        /// This is used when an operation cannot be completed because a component
        /// of the path which was expected to be a directory was not.
        ///
        /// Used in situations that correspond to the POSIX ENOTDIR error code.
        case notDirectory

        /// Unsupported operation
        ///
        /// This is used when an operation is not supported by the concrete file
        /// system implementation.
        case unsupported

        /// An unspecific operating system error at a given path.
        case unknownOSError

        /// File or folder already exists at destination.
        ///
        /// This is thrown when copying or moving a file or directory but the destination
        /// path already contains a file or folder.
        case alreadyExistsAtDestination
    }

    /// The kind of the error being raised.
    public let kind: Kind

    /// The absolute path to the file associated with the error, if available.
    public let path: AbsolutePath?

    public init(_ kind: Kind, _ path: AbsolutePath? = nil) {
        self.kind = kind
        self.path = path
    }
}

public extension FileSystemError {
    init(errno: Int32, _ path: AbsolutePath) {
        switch errno {
        case TSCLibc.EACCES:
            self.init(.invalidAccess, path)
        case TSCLibc.EISDIR:
            self.init(.isDirectory, path)
        case TSCLibc.ENOENT:
            self.init(.noEntry, path)
        case TSCLibc.ENOTDIR:
            self.init(.notDirectory, path)
        default:
            self.init(.unknownOSError, path)
        }
    }
}

/// Defines the file modes.
public enum FileMode {

    public enum Option: Int {
        case recursive
        case onlyFiles
    }

    case userUnWritable
    case userWritable
    case executable

    internal var setMode: (Int16) -> Int16 {
        switch self {
        case .userUnWritable:
            // r-x rwx rwx
            return {$0 & 0o577}
        case .userWritable:
            // -w- --- ---
            return {$0 | 0o200}
        case .executable:
            // --x --x --x
            return {$0 | 0o111}
        }
    }
}

// FIXME: Design an asynchronous story?
//
/// Abstracted access to file system operations.
///
/// This protocol is used to allow most of the codebase to interact with a
/// natural filesystem interface, while still allowing clients to transparently
/// substitute a virtual file system or redirect file system operations.
///
/// - Note: All of these APIs are synchronous and can block.
public protocol FileSystem: class {
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
    var homeDirectory: AbsolutePath { get }
    
    /// Get the caches directory of current user
    var cachesDirectory: AbsolutePath? { get }

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
public extension FileSystem {
    /// exists override with default value.
    func exists(_ path: AbsolutePath) -> Bool {
        return exists(path, followSymlink: true)
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

/// Concrete FileSystem implementation which communicates with the local file system.
private class LocalFileSystem: FileSystem {

    func isExecutableFile(_ path: AbsolutePath) -> Bool {
        // Our semantics doesn't consider directories.
        return  (self.isFile(path) || self.isSymlink(path)) && FileManager.default.isExecutableFile(atPath: path.pathString)
    }

    func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        if followSymlink {
            return FileManager.default.fileExists(atPath: path.pathString)
        }
        return (try? FileManager.default.attributesOfItem(atPath: path.pathString)) != nil
    }

    func isDirectory(_ path: AbsolutePath) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func isFile(_ path: AbsolutePath) -> Bool {
        let path = resolveSymlinks(path)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.pathString)
        return attrs?[.type] as? FileAttributeType == .typeRegular
    }

    func isSymlink(_ path: AbsolutePath) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.pathString)
        return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    func getFileInfo(_ path: AbsolutePath) throws -> FileInfo {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return FileInfo(attrs)
    }

    var currentWorkingDirectory: AbsolutePath? {
        let cwdStr = FileManager.default.currentDirectoryPath

#if _runtime(_ObjC)
        // The ObjC runtime indicates that the underlying Foundation has ObjC
        // interoperability in which case the return type of
        // `fileSystemRepresentation` is different from the Swift implementation
        // of Foundation.
        return try? AbsolutePath(validating: cwdStr)
#else
        let fsr: UnsafePointer<Int8> = cwdStr.fileSystemRepresentation
        defer { fsr.deallocate() }

        return try? AbsolutePath(validating: String(cString: fsr))
#endif
    }

    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        guard isDirectory(path) else {
            throw FileSystemError(.notDirectory, path)
        }

        guard FileManager.default.changeCurrentDirectoryPath(path.pathString) else {
            throw FileSystemError(.unknownOSError, path)
        }
    }

    var homeDirectory: AbsolutePath {
        return AbsolutePath(NSHomeDirectory())
    }
    
    var cachesDirectory: AbsolutePath? {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.flatMap { AbsolutePath($0.absoluteString) }
    }

    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
      #if canImport(Darwin)
        return try FileManager.default.contentsOfDirectory(atPath: path.pathString)
      #else
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path.pathString)
        } catch let error as NSError {
            // Fixup error from corelibs-foundation.
            if error.code == CocoaError.fileReadNoSuchFile.rawValue, !error.userInfo.keys.contains(NSLocalizedDescriptionKey) {
                var userInfo = error.userInfo
                userInfo[NSLocalizedDescriptionKey] = "The folder “\(path.basename)” doesn’t exist."
                throw NSError(domain: error.domain, code: error.code, userInfo: userInfo)
            }
            throw error
        }
      #endif
    }

    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        // Don't fail if path is already a directory.
        if isDirectory(path) { return }

        try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: recursive, attributes: [:])
    }

    func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
        let destString = relative ? destination.relative(to: path.parentDirectory).pathString : destination.pathString
        try FileManager.default.createSymbolicLink(atPath: path.pathString, withDestinationPath: destString)
    }

    func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        // Open the file.
        let fp = fopen(path.pathString, "rb")
        if fp == nil {
            throw FileSystemError(errno: errno, path)
        }
        defer { fclose(fp) }

        // Read the data one block at a time.
        let data = BufferedOutputByteStream()
        var tmpBuffer = [UInt8](repeating: 0, count: 1 << 12)
        while true {
            let n = fread(&tmpBuffer, 1, tmpBuffer.count, fp)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError(.ioError(code: errno), path)
            }
            if n == 0 {
                let errno = ferror(fp)
                if errno != 0 {
                    throw FileSystemError(.ioError(code: errno), path)
                }
                break
            }
            data <<< tmpBuffer[0..<n]
        }

        return data.bytes
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        // Open the file.
        let fp = fopen(path.pathString, "wb")
        if fp == nil {
            throw FileSystemError(errno: errno, path)
        }
        defer { fclose(fp) }

        // Write the data in one chunk.
        var contents = bytes.contents
        while true {
            let n = fwrite(&contents, 1, contents.count, fp)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError(.ioError(code: errno), path)
            }
            if n != contents.count {
                throw FileSystemError(.unknownOSError, path)
            }
            break
        }
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        // Perform non-atomic writes using the fast path.
        if !atomically {
            return try writeFileContents(path, bytes: bytes)
        }

        try bytes.withData {
            try $0.write(to: URL(fileURLWithPath: path.pathString), options: .atomic)
        }
    }

    func removeFileTree(_ path: AbsolutePath) throws {
        if self.exists(path, followSymlink: false) {
            try FileManager.default.removeItem(atPath: path.pathString)
        }
    }

    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        guard exists(path) else { return }
        func setMode(path: String) throws {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            // Skip if only files should be changed.
            if options.contains(.onlyFiles) && attrs[.type] as? FileAttributeType != .typeRegular {
                return
            }

            // Compute the new mode for this file.
            let currentMode = attrs[.posixPermissions] as! Int16
            let newMode = mode.setMode(currentMode)
            guard newMode != currentMode else { return }
            try FileManager.default.setAttributes([.posixPermissions : newMode],
                                                  ofItemAtPath: path)
        }

        try setMode(path: path.pathString)
        guard isDirectory(path) else { return }

        guard let traverse = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path.pathString),
                includingPropertiesForKeys: nil) else {
            throw FileSystemError(.noEntry, path)
        }

        if !options.contains(.recursive) {
            traverse.skipDescendants()
        }

        while let path = traverse.nextObject() {
            try setMode(path: (path as! URL).path)
        }
    }

    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        guard exists(sourcePath) else { throw FileSystemError(.noEntry, sourcePath) }
        guard !exists(destinationPath)
        else { throw FileSystemError(.alreadyExistsAtDestination, destinationPath) }
        try FileManager.default.copyItem(at: sourcePath.asURL, to: destinationPath.asURL)
    }

    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        guard exists(sourcePath) else { throw FileSystemError(.noEntry, sourcePath) }
        guard !exists(destinationPath)
        else { throw FileSystemError(.alreadyExistsAtDestination, destinationPath) }
        try FileManager.default.moveItem(at: sourcePath.asURL, to: destinationPath.asURL)
    }

    func withLock<T>(on path: AbsolutePath, type: FileLock.LockType = .exclusive, _ body: () throws -> T) throws -> T {
        let lock = FileLock(name: path.basename, cachePath: path.parentDirectory)
        return try lock.withLock(type: type, body)
    }
}

// FIXME: This class does not yet support concurrent mutation safely.
//
/// Concrete FileSystem implementation which simulates an empty disk.
public class InMemoryFileSystem: FileSystem {
    
    /// Private internal representation of a file system node.
    /// Not threadsafe.
    private class Node {
        /// The actual node data.
        let contents: NodeContents

        init(_ contents: NodeContents) {
            self.contents = contents
        }

        /// Creates deep copy of the object.
        func copy() -> Node {
           return Node(contents.copy())
        }
    }

    /// Private internal representation the contents of a file system node.
    /// Not threadsafe.
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
    /// Not threadsafe.
    private class DirectoryContents {
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

    /// The root node of the filesytem.
    private var root: Node
    
    /// Protects `root` and everything underneath it.
    /// FIXME: Using a single lock for this is a performance problem, but in
    /// reality, the only practical use for InMemoryFileSystem is for unit
    /// tests.
    private let lock = Lock()
    /// A map that keeps weak references to all locked files.
    private var lockFiles = Dictionary<AbsolutePath, WeakReference<DispatchQueue>>()
    /// Used to access lockFiles in a thread safe manner.
    private let lockFilesLock = Lock()
    
    /// Exclusive file system lock vended to clients through `withLock()`.
    // Used to ensure that DispatchQueues are releassed when they are no longer in use.
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
    /// Not threadsafe.
    private func getNode(_ path: AbsolutePath, followSymlink: Bool = true) throws -> Node? {
        func getNodeInternal(_ path: AbsolutePath) throws -> Node? {
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
                let destination = AbsolutePath(destination, relativeTo: path.parentDirectory)
                return followSymlink ? try getNodeInternal(destination) : node
            case .none:
                return nil
            }
        }

        // Get the node that corresponds to the path.
        return try getNodeInternal(path)
    }

    // MARK: FileSystem Implementation

    public func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
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

    public func isDirectory(_ path: AbsolutePath) -> Bool {
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

    public func isFile(_ path: AbsolutePath) -> Bool {
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

    public func isSymlink(_ path: AbsolutePath) -> Bool {
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

    public func isExecutableFile(_ path: AbsolutePath) -> Bool {
        // FIXME: Always return false until in-memory implementation
        // gets permission semantics.
        return false
    }

    /// Virtualized current working directory.
    public var currentWorkingDirectory: AbsolutePath? {
        return AbsolutePath("/")
    }

    public func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        throw FileSystemError(.unsupported, path)
    }

    public var homeDirectory: AbsolutePath {
        // FIXME: Maybe we should allow setting this when creating the fs.
        return AbsolutePath("/home/user")
    }
    
    public var cachesDirectory: AbsolutePath? {
        return self.homeDirectory.appending(component: "caches")
    }

    public func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
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
    
    /// Not threadsafe.
    private func _createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
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

    public func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        return try lock.withLock {
            try _createDirectory(path, recursive: recursive)
        }
    }

    public func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
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

    public func readFileContents(_ path: AbsolutePath) throws -> ByteString {
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

    public func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
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

    public func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        // In memory file system's writeFileContents is already atomic, so ignore the parameter here
        // and just call the base implementation.
        try writeFileContents(path, bytes: bytes)
    }

    public func removeFileTree(_ path: AbsolutePath) throws {
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

    public func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        // FIXME: We don't have these semantics in InMemoryFileSystem.
    }
    
    /// Private implementation of core copying function.
    /// Not threadsafe.
    private func _copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
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

    public func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        return try lock.withLock {
            try _copy(from: sourcePath, to: destinationPath)
        }
    }

    public func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
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

    public func withLock<T>(on path: AbsolutePath, type: FileLock.LockType = .exclusive, _ body: () throws -> T) throws -> T {
        let resolvedPath: AbsolutePath = try lock.withLock {
            if case let .symlink(destination) = try getNode(path)?.contents {
                return  AbsolutePath(destination, relativeTo: path.parentDirectory)
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
}

/// A rerooted view on an existing FileSystem.
///
/// This is a simple wrapper which creates a new FileSystem view into a subtree
/// of an existing filesystem. This is useful for passing to clients which only
/// need access to a subtree of the filesystem but should otherwise remain
/// oblivious to its concrete location.
///
/// NOTE: The rerooting done here is purely at the API level and does not
/// inherently prevent access outside the rerooted path (e.g., via symlinks). It
/// is designed for situations where a client is only interested in the contents
/// *visible* within a subpath and is agnostic to the actual location of those
/// contents.
public class RerootedFileSystemView: FileSystem {
    /// The underlying file system.
    private var underlyingFileSystem: FileSystem

    /// The root path within the containing file system.
    private let root: AbsolutePath

    public init(_ underlyingFileSystem: FileSystem, rootedAt root: AbsolutePath) {
        self.underlyingFileSystem = underlyingFileSystem
        self.root = root
    }

    /// Adjust the input path for the underlying file system.
    private func formUnderlyingPath(_ path: AbsolutePath) -> AbsolutePath {
        if path == AbsolutePath.root {
            return root
        } else {
            // FIXME: Optimize?
            return root.appending(RelativePath(String(path.pathString.dropFirst(1))))
        }
    }

    // MARK: FileSystem Implementation

    public func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        return underlyingFileSystem.exists(formUnderlyingPath(path), followSymlink: followSymlink)
    }

    public func isDirectory(_ path: AbsolutePath) -> Bool {
        return underlyingFileSystem.isDirectory(formUnderlyingPath(path))
    }

    public func isFile(_ path: AbsolutePath) -> Bool {
        return underlyingFileSystem.isFile(formUnderlyingPath(path))
    }

    public func isSymlink(_ path: AbsolutePath) -> Bool {
        return underlyingFileSystem.isSymlink(formUnderlyingPath(path))
    }

    public func isExecutableFile(_ path: AbsolutePath) -> Bool {
        return underlyingFileSystem.isExecutableFile(formUnderlyingPath(path))
    }

    /// Virtualized current working directory.
    public var currentWorkingDirectory: AbsolutePath? {
        return AbsolutePath("/")
    }

    public func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        throw FileSystemError(.unsupported, path)
    }

    public var homeDirectory: AbsolutePath {
        fatalError("homeDirectory on RerootedFileSystemView is not supported.")
    }
    
    public var cachesDirectory: AbsolutePath? {
        fatalError("cachesDirectory on RerootedFileSystemView is not supported.")
    }

    public func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        return try underlyingFileSystem.getDirectoryContents(formUnderlyingPath(path))
    }

    public func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        let path = formUnderlyingPath(path)
        return try underlyingFileSystem.createDirectory(path, recursive: recursive)
    }

    public func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
        let path = formUnderlyingPath(path)
        let destination = formUnderlyingPath(destination)
        return try underlyingFileSystem.createSymbolicLink(path, pointingAt: destination, relative: relative)
    }

    public func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        return try underlyingFileSystem.readFileContents(formUnderlyingPath(path))
    }

    public func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        let path = formUnderlyingPath(path)
        return try underlyingFileSystem.writeFileContents(path, bytes: bytes)
    }

    public func removeFileTree(_ path: AbsolutePath) throws {
        try underlyingFileSystem.removeFileTree(formUnderlyingPath(path))
    }

    public func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        try underlyingFileSystem.chmod(mode, path: path, options: options)
    }

    public func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try underlyingFileSystem.copy(from: formUnderlyingPath(sourcePath), to: formUnderlyingPath(sourcePath))
    }

    public func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try underlyingFileSystem.move(from: formUnderlyingPath(sourcePath), to: formUnderlyingPath(sourcePath))
    }

    public func withLock<T>(on path: AbsolutePath, type: FileLock.LockType = .exclusive, _ body: () throws -> T) throws -> T {
        return try underlyingFileSystem.withLock(on: formUnderlyingPath(path), type: type, body)
    }
}

/// Public access to the local FS proxy.
public var localFileSystem: FileSystem = LocalFileSystem()

extension FileSystem {
    /// Print the filesystem tree of the given path.
    ///
    /// For debugging only.
    public func dumpTree(at path: AbsolutePath = .root) {
        print(".")
        do {
            try recurse(fs: self, path: path)
        } catch {
            print("\(error)")
        }
    }

    /// Write bytes to the path if the given contents are different.
    public func writeIfChanged(path: AbsolutePath, bytes: ByteString) throws {
        try createDirectory(path.parentDirectory, recursive: true)

        // Return if the contents are same.
        if isFile(path), try readFileContents(path) == bytes {
            return
        }

        try writeFileContents(path, bytes: bytes)
    }

    /// Helper method to recurse and print the tree.
    private func recurse(fs: FileSystem, path: AbsolutePath, prefix: String = "") throws {
        let contents = try fs.getDirectoryContents(path)

        for (idx, entry) in contents.enumerated() {
            let isLast = idx == contents.count - 1
            let line = prefix + (isLast ? "└── " : "├── ") + entry
            print(line)

            let entryPath = path.appending(component: entry)
            if fs.isDirectory(entryPath) {
                let childPrefix = prefix + (isLast ?  "    " : "│   ")
                try recurse(fs: fs, path: entryPath, prefix: String(childPrefix))
            }
        }
    }
}

#if !os(Windows)
extension dirent {
    /// Get the directory name.
    ///
    /// This returns nil if the name is not valid UTF8.
    public var name: String? {
        var d_name = self.d_name
        return withUnsafePointer(to: &d_name) {
            String(validatingUTF8: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
    }
}
#endif
