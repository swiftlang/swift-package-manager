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

import class Dispatch.DispatchQueue
import struct SystemPackage.FileDescriptor

package struct OpenReadableFile: Sendable {
    let readChunkSize: Int

    package enum Storage {
        case local(FileDescriptor, DispatchQueue)
        case virtual([UInt8])
    }

    package let fileHandle: Storage

    package func read() async throws -> ReadableFileStream {
        switch self.fileHandle {
        case let .local(fileDescriptor, ioQueue):
            ReadableFileStream.local(
                .init(
                    fileDescriptor: fileDescriptor,
                    ioQueue: ioQueue,
                    readChunkSize: self.readChunkSize
                )
            )
        case .virtual(let array):
            ReadableFileStream.virtual(.init(bytes: array))
        }
    }
}
