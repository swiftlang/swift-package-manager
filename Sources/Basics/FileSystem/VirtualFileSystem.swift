//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import TSCBasic

fileprivate enum DirectoryNode: Codable {
    case directory(name: String, isSymlink: Bool, children: [DirectoryNode])
    case file(name: String, isExecutable: Bool, isSymlink: Bool, contents: Data?)
    case root(children: [DirectoryNode])

    var children: [DirectoryNode] {
        switch self {
        case .directory(_, _, let children): return children
        case .file(_, _, _, _): return []
        case .root(let children): return children
        }
    }

    var name: String {
        switch self {
        case .directory(let name, _, _): return name
        case .file(let name, _, _, _): return name
        case .root(_): return AbsolutePath.root.pathString
        }
    }

    var fileAttributeType: FileAttributeType {
        switch self {
        case .directory(_, _, _): return .typeDirectory
        case .file(_, _, let isSymlink, _): return isSymlink ? .typeSymbolicLink : .typeRegular
        case .root(_): return .typeDirectory
        }
    }

    var isDirectory: Bool {
        switch self {
        case .directory(_, _, _): return true
        case .file(_, _, _, _): return false
        case .root(_): return true
        }
    }

    var isFile: Bool {
        switch self {
        case .directory(_, _, _): return false
        case .file(_, _, _, _): return true
        case .root(_): return false
        }
    }

    var isRoot: Bool {
        switch self {
        case .directory(_, _, _): return false
        case .file(_, _, _, _): return false
        case .root(_): return true
        }
    }

    var isSymlink: Bool {
        switch self {
        case .directory(_, let isSymlink, _): return isSymlink
        case .file(_, _, let isSymlink, _): return isSymlink
        case .root(_): return false
        }
    }
}

private enum Errors: Swift.Error, LocalizedError {
    case noSuchFileOrDirectory(path: AbsolutePath)
    case notAFile(path: AbsolutePath)
    case readOnlyFileSystem
    case unhandledDirectoryNode(path: AbsolutePath)

    public var errorDescription: String? {
        switch self {
        case .noSuchFileOrDirectory(let path): return "no such file or directory: \(path.pathString)"
        case .notAFile(let path): return "not a file: \(path.pathString)"
        case .readOnlyFileSystem: return "read-only filesystem"
        case .unhandledDirectoryNode(let path): return "unhandled directory node: \(path.pathString)"
        }
    }
}

private extension FileSystem {
    func getDirectoryNodes(_ path: AbsolutePath, includeContents: [AbsolutePath]) throws -> [DirectoryNode] {
        return try getDirectoryContents(path).compactMap {
            let current = path.appending(component: $0)
            let isSymlink = isSymlink(current)

            if isFile(current) {
                let contents: Data?
                if includeContents.contains(current) {
                    contents = try readFileContents(current)
                } else {
                    contents = nil
                }
                return .file(name: $0, isExecutable: isExecutableFile(current), isSymlink: isSymlink, contents: contents)
            } else if isDirectory(current) {
                if $0.hasPrefix(".") { return nil } // we ignore hidden files
                return .directory(name: $0, isSymlink: isSymlink, children: try getDirectoryNodes(current, includeContents: includeContents))
            } else {
                throw Errors.unhandledDirectoryNode(path: current)
            }
        }
    }
}

/// A JSON-backed, read-only virtual file system.
public class VirtualFileSystem: FileSystem {
    private let root: DirectoryNode

    public init(path: AbsolutePath, fs: FileSystem) throws {
        self.root = try JSONDecoder.makeWithDefaults().decode(path: path, fileSystem: fs, as: DirectoryNode.self)
        assert(self.root.isRoot, "VFS needs to have a root node")
    }

    /// Write information about the directory tree at `directoryPath` into a JSON file at `vfsPath`. This can later be used to construct a `VirtualFileSystem` object.
    public static func serializeDirectoryTree(_ directoryPath: AbsolutePath, into vfsPath: AbsolutePath, fs: FileSystem, includeContents: [AbsolutePath]) throws {
        let data = try JSONEncoder.makeWithDefaults().encode(DirectoryNode.root(children: fs.getDirectoryNodes(directoryPath, includeContents: includeContents)))
        try data.write(to: URL(fileURLWithPath: vfsPath.pathString))
    }

    private func findNode(_ path: AbsolutePath, followSymlink: Bool) -> DirectoryNode? {
        var current: DirectoryNode? = self.root
        for component in path.components {
            if component == AbsolutePath.root.pathString { continue }
            guard followSymlink, current?.isSymlink == false else { return nil }
            current = current?.children.first(where: { $0.name == component })
        }
        return current
    }

    public func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        return findNode(path, followSymlink: followSymlink) != nil
    }

    public func isDirectory(_ path: AbsolutePath) -> Bool {
        return findNode(path, followSymlink: true)?.isDirectory == true
    }

    public func isFile(_ path: AbsolutePath) -> Bool {
        return findNode(path, followSymlink: true)?.isFile == true
    }

    public func isExecutableFile(_ path: AbsolutePath) -> Bool {
        guard let node = findNode(path, followSymlink: true) else { return false }
        if case let .file(_, isExecutable, _, _) = node {
            return isExecutable
        } else {
            return false
        }
    }

    public func isSymlink(_ path: AbsolutePath) -> Bool {
        return findNode(path, followSymlink: true)?.isSymlink == true
    }

    public func isReadable(_ path: AbsolutePath) -> Bool {
        return self.exists(path)
    }

    public func isWritable(_ path: AbsolutePath) -> Bool {
        return false
    }

    public func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        guard let node = findNode(path, followSymlink: true) else { throw Errors.noSuchFileOrDirectory(path: path) }
        return node.children.map { $0.name }
    }

    public let currentWorkingDirectory: AbsolutePath? = nil

    public func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public var homeDirectory = AbsolutePath.root

    public var cachesDirectory: AbsolutePath? = nil

    public var tempDirectory = AbsolutePath.root

    public func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
        throw Errors.readOnlyFileSystem
    }

    public func removeFileTree(_ path: AbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        throw Errors.readOnlyFileSystem
    }

    public func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        guard let node = findNode(path, followSymlink: true) else { throw Errors.noSuchFileOrDirectory(path: path) }
        switch node {
        case .directory(_, _, _): throw Errors.notAFile(path: path)
        case .file(_, _, _, let contents):
            if let contents {
                return ByteString(contents)
            } else {
                return ""
            }
        case .root(_): throw Errors.notAFile(path: path)
        }
    }

    public func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        throw Errors.readOnlyFileSystem
    }

    public func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        throw Errors.readOnlyFileSystem
    }

    public func getFileInfo(_ path: AbsolutePath) throws -> FileInfo {
        guard let node = findNode(path, followSymlink: true) else { throw Errors.noSuchFileOrDirectory(path: path) }

        let attrs: [FileAttributeKey: Any] = [
            .systemNumber: NSNumber(value: UInt64(0)),
            .systemFileNumber: UInt64(0),
            .posixPermissions: NSNumber(value: Int16(0)),
            .type: node.fileAttributeType,
            .size: UInt64(0),
            .modificationDate: Date(),
        ]
        return FileInfo(attrs)
    }
}

// `VirtualFileSystem` is read-only, so it can be marked as `Sendable`.
extension VirtualFileSystem: @unchecked Sendable {}
