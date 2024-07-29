//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@preconcurrency import struct SystemPackage.FilePath

/// In-memory implementation of `AsyncFileSystem` for mocking and testing purposes.
package actor MockFileSystem: AsyncFileSystem {
    /// The default size of chunks read by this file system.
    package static let defaultChunkSize = 512 * 1024

    /// Size of chunks read by this instance of file system.
    let readChunkSize: Int

    /// Underlying in-memory dictionary-based storage for this mock file system.
    final class Storage {
        init(_ content: [FilePath: [UInt8]]) {
            self.content = content
        }

        var content: [FilePath: [UInt8]]
    }

    /// Concrete instance of the underlying storage used by this file system.
    private let storage: Storage
    
    /// Creates a new instance of the mock file system.
    /// - Parameters:
    ///   - content: Dictionary of paths to their in-memory contents to use for seeding the file system.
    ///   - readChunkSize: Size of chunks produce by this file system when reading files.
    package init(content: [FilePath: [UInt8]] = [:], readChunkSize: Int = defaultChunkSize) {
        self.storage = .init(content)
        self.readChunkSize = readChunkSize
    }

    /// 
    func append(path: FilePath, bytes: some Sequence<UInt8>) {
        storage.content[path, default: []].append(contentsOf: bytes)
    }

    package func withOpenReadableFile<T: Sendable>(
        _ path: FilePath,
        _ body: (OpenReadableFile) async throws -> T
    ) async throws -> T {
        guard let bytes = storage.content[path] else {
            throw AsyncFileSystemError.fileDoesNotExist(path)
        }
        return try await body(.init(readChunkSize: self.readChunkSize, fileHandle: .mock(bytes)))
    }

    package func withOpenWritableFile<T: Sendable>(
        _ path: FilePath,
        _ body: (OpenWritableFile) async throws -> T
    ) async throws -> T {
        try await body(.init(storage: .mock(self), path: path))
    }
}
