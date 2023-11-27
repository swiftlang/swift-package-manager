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
    @available(*, noasync, message: "Use the async alternative")
    func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    /// Asynchronously compress the contents of a directory to a destination archive.
    ///
    /// - Parameters:
    ///   - directory: The `AbsolutePath` to the archive to extract.
    ///   - destinationPath: The `AbsolutePath` to the directory to extract to.
    ///   - completion: The completion handler that will be called when the operation finishes to notify of its success.
    @available(*, noasync, message: "Use the async alternative")
    func compress(
        directory: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    /// Asynchronously validates if a file is an archive.
    ///
    /// - Parameters:
    ///   - path: The `AbsolutePath` to the archive to validate.
    ///   - completion: The completion handler that will be called when the operation finishes to notify of its success.
    @available(*, noasync, message: "Use the async alternative")
    func validate(
        path: AbsolutePath,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
}

extension Archiver {
    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws {
        try await safe_async {
            self.extract(from: archivePath, to: destinationPath, completion: $0)
        }
    }

    public func compress(
        directory: AbsolutePath,
        to: AbsolutePath
    ) async throws {
        try await safe_async {
            self.compress(directory: directory, to: to, completion: $0)
        }
    }

    public func validate(
        path: AbsolutePath
    ) async throws -> Bool {
        try await safe_async {
            self.validate(path: path, completion: $0)
        }
    }
}
