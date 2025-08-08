import Foundation
import Basics

func getFiles(atPath path: String, matchingExtension fileExtension: String) -> [URL] {
    let fileManager = FileManager.default
    var matchingFiles: [URL] = []

    guard
        let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
    else {
        print("Error: Could not create enumerator for path: \(path)")
        return []
    }

    for case let fileURL as URL in enumerator {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if let isRegularFile = resourceValues.isRegularFile, isRegularFile {
                if fileURL.pathExtension.lowercased() == fileExtension.lowercased() {
                    matchingFiles.append(fileURL)
                }
            }
        } catch {
            print("Error retrieving resource values for \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
    return matchingFiles
}

/// Returns all files that match the given extension in the specified directory.
///
/// - Parameters:
///   - directory: The directory to search in (AbsolutePath)
///   - extension: The file extension to match (without the leading dot)
///   - recursive: Whether to search subdirectories recursively (default: true)
///   - fileSystem: The file system to use for operations (defaults to localFileSystem)
/// - Returns: An array of AbsolutePath objects
/// - Throws: FileSystemError if the directory cannot be accessed or enumerated
public func getFiles(
    in directory: AbsolutePath,
    matchingExtension extension: String,
    recursive: Bool = true,
    fileSystem: FileSystem = localFileSystem
) throws -> [AbsolutePath] {
    var matchingFiles: [AbsolutePath] = []
    let normalizedExtension = `extension`.lowercased()

    guard fileSystem.exists(directory) else {
        throw StringError("Directory does not exist: \(directory)")
    }

    guard fileSystem.isDirectory(directory) else {
        throw StringError("Path is not a directory: \(directory)")
    }

    if recursive {
        try fileSystem.enumerate(directory: directory) { filePath in
            if fileSystem.isFile(filePath) {
                if let fileExtension = filePath.extension?.lowercased(),
                    fileExtension == normalizedExtension
                {
                    matchingFiles.append(filePath)
                }
            }
        }
    } else {
        // Non-recursive: only check direct children
        let contents = try fileSystem.getDirectoryContents(directory)
        for item in contents {
            let itemPath = directory.appending(component: item)
            if fileSystem.isFile(itemPath) {
                if let fileExtension = itemPath.extension?.lowercased(),
                    fileExtension == normalizedExtension
                {
                    matchingFiles.append(itemPath)
                }
            }
        }
    }

    return matchingFiles
}

/// Returns all files that match the given extension in the specified directory.
///
/// - Parameters:
///   - directory: The directory to search in (RelativePath)
///   - extension: The file extension to match (without the leading dot)
///   - recursive: Whether to search subdirectories recursively (default: true)
///   - fileSystem: The file system to use for operations (defaults to localFileSystem)
/// - Returns: An array of RelativePath objects
/// - Throws: FileSystemError if the directory cannot be accessed or enumerated
public func getFiles(
    in directory: RelativePath,
    matchingExtension extension: String,
    recursive: Bool = true,
    fileSystem: FileSystem = localFileSystem
) throws -> [RelativePath] {
    // Convert RelativePath to AbsolutePath for enumeration
    guard let currentWorkingDirectory = fileSystem.currentWorkingDirectory else {
        throw StringError("Cannot determine current working directory")
    }

    let absoluteDirectory = currentWorkingDirectory.appending(directory)
    let absoluteResults = try getFiles(
        in: absoluteDirectory,
        matchingExtension: `extension`,
        recursive: recursive,
        fileSystem: fileSystem
    )

    // Convert results back to RelativePath
    return absoluteResults.map { absolutePath in
        absolutePath.relative(to: currentWorkingDirectory)
    }
}
