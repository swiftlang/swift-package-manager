/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Dispatch

/// An `Archiver` that handles ZIP archives using the command-line `zip` and `unzip` tools.
public struct ZipArchiver: Archiver {
    public var supportedExtensions: Set<String> { ["zip"] }

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Creates a `ZipArchiver`.
    ///
    /// - Parameters:
    ///   - fileSystem: The file-system to used by the `ZipArchiver`.
    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard fileSystem.exists(archivePath) else {
            completion(.failure(FileSystemError(.noEntry, archivePath)))
            return
        }

        guard fileSystem.isDirectory(destinationPath) else {
            completion(.failure(FileSystemError(.notDirectory, destinationPath)))
            return
        }

        Process.popen(arguments: ["unzip", archivePath.pathString, "-d", destinationPath.pathString], queue: .sharedConcurrent) { result in
            completion(result.tryMap { processResult in
                guard processResult.exitStatus == .terminated(code: 0) else {
                    throw try StringError(processResult.utf8stderrOutput())
                }
            })
        }
    }

    public func validate(path: AbsolutePath, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard fileSystem.exists(path) else {
            completion(.failure(FileSystemError(.noEntry, path)))
            return
        }

        Process.popen(arguments: ["unzip", "-t", path.pathString], queue: .sharedConcurrent) { result in
            completion(result.tryMap { processResult in
                return processResult.exitStatus == .terminated(code: 0)
            })
        }
    }
}
