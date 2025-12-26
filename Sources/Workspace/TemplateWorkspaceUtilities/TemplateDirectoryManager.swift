//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

/// A helper for managing temporary directories used in filesystem operations.
public struct TemporaryDirectoryHelper {
    let fileSystem: FileSystem

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    /// Creates a temporary directory with an optional name.
    public func createTemporaryDirectory(named name: String? = nil) throws -> Basics.AbsolutePath {
        let dirName = name ?? UUID().uuidString
        let dirPath = try fileSystem.tempDirectory.appending(component: dirName)
        try self.fileSystem.createDirectory(dirPath)
        return dirPath
    }

    /// Creates multiple subdirectories within a parent directory.
    public func createSubdirectories(in parent: Basics.AbsolutePath, names: [String]) throws -> [Basics.AbsolutePath] {
        try names.map { name in
            let path = parent.appending(component: name)
            try self.fileSystem.createDirectory(path)
            return path
        }
    }

    /// Checks if a directory exists at the given path.
    public func directoryExists(_ path: Basics.AbsolutePath) -> Bool {
        self.fileSystem.exists(path)
    }

    /// Removes a directory if it exists.
    public func removeDirectoryIfExists(_ path: Basics.AbsolutePath) throws {
        if self.fileSystem.exists(path) {
            try self.fileSystem.removeFileTree(path)
        }
    }

    /// Copies the contents of one directory to another.
    public func copyDirectoryContents(from sourceDir: AbsolutePath, to destinationDir: AbsolutePath) throws {
        let contents = try fileSystem.getDirectoryContents(sourceDir)
        for entry in contents {
            let source = sourceDir.appending(component: entry)
            let destination = destinationDir.appending(component: entry)
            try self.fileSystem.copy(from: source, to: destination)
        }
    }
}

/// Errors that can occur during directory management operations.
public enum DirectoryManagerError: Error, CustomStringConvertible, Equatable {
    case foundManifestFile(path: Basics.AbsolutePath)
    case cleanupFailed(path: Basics.AbsolutePath?)

    public var description: String {
        switch self {
        case .foundManifestFile(let path):
            return "Package.swift was found in \(path)."
        case .cleanupFailed(let path):
            let dir = path?.pathString ?? "<unknown>"
            return "Failed to clean up directory at \(dir)"
        }
    }
}
