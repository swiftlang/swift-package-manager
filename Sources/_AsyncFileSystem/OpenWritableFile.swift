//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

internal import class Dispatch.DispatchQueue
internal import struct SystemPackage.FileDescriptor
internal import struct SystemPackage.FilePath

/// A write-only thread-safe handle to an open file.
package actor OpenWritableFile: WritableStream {
    /// Underlying storage for this file handle, dependent on the file system type that produced it.
    enum Storage {
        /// Operating system file descriptor and a queue used for reading from that file descriptor without blocking
        /// the Swift Concurrency thread pool.
        case real(FileDescriptor, DispatchQueue)
        
        /// Reference to the ``MockFileSystem`` actor that provides file storage.
        case mock(MockFileSystem)
    }
    
    /// Concrete instance of underlying storage.
    let storage: Storage

    /// Absolute path to the file represented by this file handle.
    let path: FilePath

    /// Whether the underlying file descriptor has been closed.
    private var isClosed = false
    
    /// Creates a new write-only file handle.
    /// - Parameters:
    ///   - storage: Underlying storage for the file.
    ///   - path: Absolute path to the file on the file system that provides `storage`.
    init(storage: OpenWritableFile.Storage, path: FilePath) {
        self.storage = storage
        self.path = path
    }
    
    /// Writes a sequence of bytes to the buffer.
    package func write(_ bytes: some Collection<UInt8> & Sendable) async throws {
        assert(!isClosed)
        switch self.storage {
        case let .real(fileDescriptor, queue):
            let path = self.path
            try await queue.scheduleOnQueue {
                do {
                    let writtenBytesCount = try fileDescriptor.writeAll(bytes)
                    assert(bytes.count == writtenBytesCount)
                } catch {
                    throw error.attach(path)
                }
            }
        case let .mock(storage):
            await storage.write(path: self.path, bytes: bytes)
        }
    }

    /// Closes the underlying stream handle. It is a programmer error to write to a stream after it's closed.
    package func close() async throws {
        isClosed = true

        guard case let .real(fileDescriptor, queue) = self.storage else {
            return
        }

        try await queue.scheduleOnQueue {
            try fileDescriptor.close()
        }
    }
}

