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
        try fileSystem.createDirectory(dirPath)
        return dirPath
    }

    /// Creates multiple subdirectories within a parent directory.
    public func createSubdirectories(in parent: Basics.AbsolutePath, names: [String]) throws -> [Basics.AbsolutePath] {
        return try names.map { name in
            let path = parent.appending(component: name)
            try fileSystem.createDirectory(path)
            return path
        }
    }

    /// Checks if a directory exists at the given path.
    public func directoryExists(_ path: Basics.AbsolutePath) -> Bool {
        return fileSystem.exists(path)
    }

    /// Removes a directory if it exists.
    public func removeDirectoryIfExists(_ path: Basics.AbsolutePath) throws {
        if fileSystem.exists(path) {
            try fileSystem.removeFileTree(path)
        }
    }

    /// Copies the contents of one directory to another.
    public func copyDirectoryContents(from sourceDir: AbsolutePath, to destinationDir: AbsolutePath) throws {
        let contents = try fileSystem.getDirectoryContents(sourceDir)
        for entry in contents {
            let source = sourceDir.appending(component: entry)
            let destination = destinationDir.appending(component: entry)
            try fileSystem.copy(from: source, to: destination)
        }
    }
}

/// Errors that can occur during directory management operations.
public enum DirectoryManagerError: Error, CustomStringConvertible {
    case failedToRemoveDirectory(path: Basics.AbsolutePath, underlying: Error)
    case foundManifestFile(path: Basics.AbsolutePath)
    case cleanupFailed(path: Basics.AbsolutePath?, underlying: Error)

    public var description: String {
        switch self {
        case .failedToRemoveDirectory(let path, let error):
            return "Failed to remove directory at \(path): \(error.localizedDescription)"
        case .foundManifestFile(let path):
            return "Package.swift was found in \(path)."
        case .cleanupFailed(let path, let error):
            let dir = path?.pathString ?? "<unknown>"
            return "Failed to clean up directory at \(dir): \(error.localizedDescription)"
        }
    }
}
