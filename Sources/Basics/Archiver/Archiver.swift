//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import struct Foundation.URL

/// The `Archiver` protocol abstracts away the different operations surrounding archives.
public protocol Archiver: Sendable {
    /// A set of extensions the current archiver supports.
    var supportedExtensions: Set<String> { get }

    /// Asynchronously extracts the contents of an archive to a destination folder.
    ///
    /// - Parameters:
    ///   - archivePath: The `AbsolutePath` to the archive to extract.
    ///   - destinationPath: The `AbsolutePath` to the directory to extract to.
    func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws

    /// Asynchronously compress the contents of a directory to a destination archive.
    ///
    /// - Parameters:
    ///   - directory: The `AbsolutePath` to the directory to add to the archive
    ///   - destinationPath: The `AbsolutePath` to the archive
    func compress(
        directory: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws

    /// Asynchronously compress the contents of a list of directories to a destination archive.
    ///
    /// - Parameters:
    ///   - paths: The `RelativePath`s to the files or directories to archive
    ///   - parent: The `AbsolutePath` to the parent directory to archive from
    ///   - destinationPath: The `AbsolutePath` to the archive
    func compress(
        paths: [RelativePath],
        from parent: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws

    /// Asynchronously validates if a file is an archive.
    ///
    /// - Parameters:
    ///   - path: The `AbsolutePath` to the archive to validate.
    func validate(
        path: AbsolutePath
    ) async throws -> Bool
}

extension Archiver {
    /// Asynchronously compress the contents of a directory to a destination archive.
    ///
    /// - Parameters:
    ///   - directory: The `AbsolutePath` to the directory to add to the archive
    ///   - destinationPath: The `AbsolutePath` to the archive
    public func compress(
        directory: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws {
        try await self.compress(
            paths: [RelativePath(validating: directory.basename)],
            from: directory.parentDirectory,
            to: destinationPath
        )
    }

    package func isFileSupported(_ lastPathComponent: String) -> Bool {
        self.supportedExtensions.contains(where: { lastPathComponent.hasSuffix($0) })
    }
}
