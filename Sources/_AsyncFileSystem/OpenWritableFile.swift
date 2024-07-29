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
@preconcurrency import struct SystemPackage.FileDescriptor
import struct SystemPackage.FilePath

package actor OpenWritableFile: WritableStream {
    enum Error: Swift.Error {
        case system(path: FilePath, underlying: any Swift.Error)
    }

    enum Storage {
        case real(DispatchQueue, FileDescriptor)
        case mock(MockFileSystem)
    }

    let storage: Storage
    let path: FilePath
    private var isClosed = false

    init(storage: OpenWritableFile.Storage, path: FilePath) {
        self.storage = storage
        self.path = path
    }

    package func write(_ bytes: some Collection<UInt8> & Sendable) async throws {
        assert(!isClosed)
        switch self.storage {
        case let .real(queue, fileDescriptor):
            let path = self.path
            try await queue.scheduleOnQueue {
                do {
                    let writtenBytesCount = try fileDescriptor.writeAll(bytes)
                    assert(bytes.count == writtenBytesCount)
                } catch {
                    throw error.attach(path: path)
                }
            }
        case let .mock(storage):
            await storage.append(path: self.path, bytes: bytes)
        }
    }

    package func close() async throws {
        isClosed = true

        guard case let .real(queue, fileDescriptor) = self.storage else {
            return
        }

        try await queue.scheduleOnQueue {
            try fileDescriptor.close()
        }
    }
}

