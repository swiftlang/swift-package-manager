/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Dispatch

/// The `Archiver` protocol abstracts away the different operations surrounding archives.
public protocol Archiver {

    /// A set of extensions the current archiver supports.
    var supportedExtensions: Set<String> { get }

    /// Asynchronously extracts the contents of an archive to a destination folder.
    ///
    /// - Parameters:
    ///   - archivePath: The `AbsolutePath` to the archive to extract.
    ///   - destinationPath: The `AbsolutePath` to the directory to extract to.
    ///   - completion: The completion handler that will be called when the operation finishes to notify of its success.
    func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

/// An `Archiver` that handles ZIP archives using the command-line `zip` and `unzip` tools.
public struct ZipArchiver: Archiver {
    public var supportedExtensions: Set<String> { ["zip"] }

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Creates a `ZipArchiver`.
    ///
    /// - Parameters:
    ///   - fileSystem: The file-system to used by the `ZipArchiver`.
    public init(fileSystem: FileSystem = localFileSystem) {
        self.fileSystem = fileSystem
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard fileSystem.exists(archivePath) else {
            completion(.failure(FileSystemError.noEntry))
            return
        }

        guard fileSystem.isDirectory(destinationPath) else {
            completion(.failure(FileSystemError.notDirectory))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try Process.popen(args: "unzip", archivePath.pathString, "-d", destinationPath.pathString)
                guard result.exitStatus == .terminated(code: 0) else {
                    throw try StringError(result.utf8stderrOutput())
                }

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
