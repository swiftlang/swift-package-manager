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
import struct TSCBasic.ByteString
import struct TSCBasic.FileInfo
import enum TSCBasic.FileMode

private enum DirectoryNode: Codable {
    case directory(name: String, isSymlink: Bool, children: [DirectoryNode])
    case file(name: String, isExecutable: Bool, isSymlink: Bool, contents: Data?)
    case root(children: [DirectoryNode])

    var children: [DirectoryNode] {
        switch self {
        case .directory(_, _, let children): return children
        case .file: return []
        case .root(let children): return children
        }
    }

    var name: String {
        switch self {
        case .directory(let name, _, _): return name
        case .file(let name, _, _, _): return name
        case .root: return AbsolutePath.root.pathString
        }
    }

    var fileAttributeType: FileAttributeType {
        switch self {
        case .directory: return .typeDirectory
        case .file(_, _, let isSymlink, _): return isSymlink ? .typeSymbolicLink : .typeRegular
        case .root: return .typeDirectory
        }
    }

    var isDirectory: Bool {
        switch self {
        case .directory: return true
        case .file: return false
        case .root: return true
        }
    }

    var isFile: Bool {
        switch self {
        case .directory: return false
        case .file: return true
        case .root: return false
        }
    }

    var isRoot: Bool {
        switch self {
        case .directory: return false
        case .file: return false
        case .root: return true
        }
    }

    var isSymlink: Bool {
        switch self {
        case .directory(_, let isSymlink, _): return isSymlink
        case .file(_, _, let isSymlink, _): return isSymlink
        case .root: return false
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

extension FileSystem {
    fileprivate func getDirectoryNodes(
        _ path: AbsolutePath,
        includeContents: [AbsolutePath]
    ) throws -> [DirectoryNode] {
        try getDirectoryContents(path).compactMap {
            let current = path.appending(component: $0)
            let isSymlink = isSymlink(current)

            if isFile(current) {
                let contents: Data?
                if includeContents.contains(current) {
                    contents = try readFileContents(current)
                } else {
                    contents = nil
                }
                return .file(
                    name: $0,
                    isExecutable: isExecutableFile(current),
                    isSymlink: isSymlink,
                    contents: contents
                )
            } else if isDirectory(current) {
                if $0.hasPrefix(".") { return nil } // we ignore hidden files
                return .directory(
                    name: $0,
                    isSymlink: isSymlink,
                    children: try getDirectoryNodes(current, includeContents: includeContents)
                )
            } else {
                throw Errors.unhandledDirectoryNode(path: current)
            }
        }
    }
}

/// A JSON-backed, read-only virtual file system.
public class VirtualFileSystem: FileSystem {
    private let root: DirectoryNode

    public init(path: TSCAbsolutePath, fs: FileSystem) throws {
        self.root = try JSONDecoder.makeWithDefaults()
            .decode(path: AbsolutePath(path), fileSystem: fs, as: DirectoryNode.self)
        assert(self.root.isRoot, "VFS needs to have a root node")
    }

    /// Write information about the directory tree at `directoryPath` into a JSON file at `vfsPath`. This can later be used to construct a `VirtualFileSystem` object.
    public static func serializeDirectoryTree(
        _ directoryPath: AbsolutePath,
        into vfsPath: AbsolutePath,
        fs: FileSystem,
        includeContents: [AbsolutePath]
    ) throws {
        let data = try JSONEncoder.makeWithDefaults().encode(
            DirectoryNode.root(
                children: fs.getDirectoryNodes(
                    directoryPath,
                    includeContents: includeContents
                )
            )
        )
        try data.write(to: URL(fileURLWithPath: vfsPath.pathString))
    }

    private func findNode(_ path: TSCAbsolutePath, followSymlink: Bool) -> DirectoryNode? {
        var current: DirectoryNode? = self.root
        for component in path.components {
            if component == AbsolutePath.root.pathString { continue }
            guard followSymlink, current?.isSymlink == false else { return nil }
            current = current?.children.first(where: { $0.name == component })
        }
        return current
    }

    public func exists(_ path: TSCAbsolutePath, followSymlink: Bool) -> Bool {
        findNode(path, followSymlink: followSymlink) != nil
    }

    public func isDirectory(_ path: TSCAbsolutePath) -> Bool {
        findNode(path, followSymlink: true)?.isDirectory == true
    }

    public func isFile(_ path: TSCAbsolutePath) -> Bool {
        findNode(path, followSymlink: true)?.isFile == true
    }

    public func isExecutableFile(_ path: TSCAbsolutePath) -> Bool {
        guard let node = findNode(path, followSymlink: true) else { return false }
        if case .file(_, let isExecutable, _, _) = node {
            return isExecutable
        } else {
            return false
        }
    }

    public func isSymlink(_ path: TSCAbsolutePath) -> Bool {
        findNode(path, followSymlink: true)?.isSymlink == true
    }

    public func isReadable(_ path: TSCAbsolutePath) -> Bool {
        self.exists(path)
    }

    public func isWritable(_: TSCAbsolutePath) -> Bool {
        false
    }

    public func getDirectoryContents(_ path: TSCAbsolutePath) throws -> [String] {
        guard let node = findNode(path, followSymlink: true)
        else { throw Errors.noSuchFileOrDirectory(path: AbsolutePath(path)) }
        return node.children.map(\.name)
    }

    public let currentWorkingDirectory: TSCAbsolutePath? = nil

    public func changeCurrentWorkingDirectory(to path: TSCAbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public var homeDirectory = TSCAbsolutePath.root

    public var cachesDirectory: TSCAbsolutePath? = nil

    public var tempDirectory = TSCAbsolutePath.root

    public func createSymbolicLink(
        _ path: TSCAbsolutePath,
        pointingAt destination: TSCAbsolutePath,
        relative: Bool
    ) throws {
        throw Errors.readOnlyFileSystem
    }

    public func removeFileTree(_: TSCAbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public func copy(from sourcePath: TSCAbsolutePath, to destinationPath: TSCAbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public func move(from sourcePath: TSCAbsolutePath, to destinationPath: TSCAbsolutePath) throws {
        throw Errors.readOnlyFileSystem
    }

    public func createDirectory(_ path: TSCAbsolutePath, recursive: Bool) throws {
        throw Errors.readOnlyFileSystem
    }

    public func readFileContents(_ path: TSCAbsolutePath) throws -> ByteString {
        guard let node = findNode(path, followSymlink: true)
        else { throw Errors.noSuchFileOrDirectory(path: AbsolutePath(path)) }
        switch node {
        case .directory: throw Errors.notAFile(path: AbsolutePath(path))
        case .file(_, _, _, let contents):
            if let contents {
                return ByteString(contents)
            } else {
                return ""
            }
        case .root: throw Errors.notAFile(path: AbsolutePath(path))
        }
    }

    public func writeFileContents(_ path: TSCAbsolutePath, bytes: ByteString) throws {
        throw Errors.readOnlyFileSystem
    }

    public func chmod(_ mode: FileMode, path: TSCAbsolutePath, options: Set<FileMode.Option>) throws {
        throw Errors.readOnlyFileSystem
    }

    public func getFileInfo(_ path: TSCAbsolutePath) throws -> FileInfo {
        guard let node = findNode(path, followSymlink: true)
        else { throw Errors.noSuchFileOrDirectory(path: AbsolutePath(path)) }

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
