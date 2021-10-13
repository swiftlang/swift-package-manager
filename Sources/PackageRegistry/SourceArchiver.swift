/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import TSCBasic
import TSCUtility

import Dispatch

/// An `Archiver` that handles source archives.
///
/// Source archives created with `swift package archive-source`
/// have a top-level directory prefix (for example, `LinkedList-1.1.1/`).
/// Unfortunately, the `unzip` command used by `ZipArchiver` doesn't have an option for
/// ignoring this top-level prefix.
/// Rather than performing additional (possibly unsafe) file system operations,
/// this `Archiver` delegates to `tar`, which has a built-in `--strip-components=` option.
struct SourceArchiver: Archiver {
    public var supportedExtensions: Set<String> { ["zip"] }

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Creates a `SourceArchiver`.
    ///
    /// - Parameters:
    ///   - fileSystem: The file-system to used by the `SourceArchiver`.
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

        // TODO: consider calling `libarchive` or some other library directly instead of spawning a process
        DispatchQueue.sharedConcurrent.async {
            do {
                let result = try Process.popen(args: "bsdtar",
                                                     "--strip-components=1",
                                                     "-xvf",
                                                     archivePath.pathString,
                                                     "-C", destinationPath.pathString)
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
