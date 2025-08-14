import Basics
import Foundation

public struct TemporaryDirectoryHelper {
    let fileSystem: FileSystem

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    public func createTemporaryDirectory(named name: String? = nil) throws -> Basics.AbsolutePath {
        let dirName = name ?? UUID().uuidString
        let dirPath = try fileSystem.tempDirectory.appending(component: dirName)
        try fileSystem.createDirectory(dirPath)
        return dirPath
    }

    public func createSubdirectories(in parent: Basics.AbsolutePath, names: [String]) throws -> [Basics.AbsolutePath] {
        return try names.map { name in
            let path = parent.appending(component: name)
            try fileSystem.createDirectory(path)
            return path
        }
    }

    public func directoryExists(_ path: Basics.AbsolutePath) -> Bool {
        return fileSystem.exists(path)
    }

    public func removeDirectoryIfExists(_ path: Basics.AbsolutePath) throws {
        if fileSystem.exists(path) {
            try fileSystem.removeFileTree(path)
        }
    }

    public func copyDirectory(from: Basics.AbsolutePath, to: Basics.AbsolutePath) throws {
        try fileSystem.copy(from: from, to: to)
    }
}

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
