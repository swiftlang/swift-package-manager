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

internal import class Dispatch.DispatchQueue
internal import struct SystemPackage.FileDescriptor

/// A read-only thread-safe handle to an open file.
package struct OpenReadableFile: Sendable {
    /// Maximum size of chunks in bytes produced when reading this file handle.
    let chunkSize: Int

    /// Underlying storage for this file handle, dependent on the file system type that produced it.
    enum Storage {
        /// Operating system file descriptor and a queue used for reading from that file descriptor without blocking
        /// the Swift Concurrency thread pool.
        case real(FileDescriptor, DispatchQueue)

        /// Complete contents of the file represented by this handle stored in memory as an array of bytes.
        case mock([UInt8])
    }

    /// Concrete instance of underlying file storage.
    let fileHandle: Storage
    
    /// Creates a readable ``AsyncSequence`` that can be iterated on to read from this file handle.
    /// - Returns: `ReadableFileStream` value conforming to ``AsyncSequence``, ready for asynchronous iteration.
    package func read() async throws -> ReadableFileStream {
        switch self.fileHandle {
        case let .real(fileDescriptor, ioQueue):
            return ReadableFileStream.real(
                .init(
                    fileDescriptor: fileDescriptor,
                    ioQueue: ioQueue,
                    readChunkSize: self.chunkSize
                )
            )
            
        case .mock(let array):
            return ReadableFileStream.mock(.init(bytes: array, chunkSize: self.chunkSize))
        }
    }
}
