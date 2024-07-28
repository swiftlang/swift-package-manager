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

import _Concurrency
import SystemPackage
import class Dispatch.DispatchQueue

package enum ReadableFileStream: AsyncSequence {
    package typealias Element = [UInt8]

    case local(LocalReadableFileStream)
    case virtual(VirtualReadableFileStream)

    package enum Iterator: AsyncIteratorProtocol {
        case local(LocalReadableFileStream.Iterator)
        case virtual(VirtualReadableFileStream.Iterator)

        package func next() async throws -> [UInt8]? {
            switch self {
            case .local(let local):
                try await local.next()
            case .virtual(let virtual):
                try await virtual.next()
            }
        }
    }

    package func makeAsyncIterator() -> Iterator {
        switch self {
        case .local(let local):
            .local(local.makeAsyncIterator())
        case .virtual(let virtual):
            .virtual(virtual.makeAsyncIterator())
        }
    }
}

package struct LocalReadableFileStream: AsyncSequence {
    package typealias Element = [UInt8]

    let fileDescriptor: FileDescriptor
    let ioQueue: DispatchQueue
    let readChunkSize: Int

    package final class Iterator: AsyncIteratorProtocol {
        init(_ fileDescriptor: FileDescriptor, ioQueue: DispatchQueue, readChunkSize: Int) {
            self.fileDescriptor = fileDescriptor
            self.ioQueue = ioQueue
            self.readChunkSize = readChunkSize
        }

        private let fileDescriptor: FileDescriptor
        private let ioQueue: DispatchQueue
        private let readChunkSize: Int

        package func next() async throws -> [UInt8]? {
            let chunkSize = self.readChunkSize
            let fileDescriptor = self.fileDescriptor

            return try await ioQueue.scheduleOnQueue {
                var buffer = [UInt8](repeating: 0, count: chunkSize)

                let bytesRead = try buffer.withUnsafeMutableBytes {
                    try fileDescriptor.read(into: $0)
                }

                guard bytesRead > 0 else {
                    return nil
                }

                buffer.removeLast(chunkSize - bytesRead)
                return buffer
            }
        }
    }

    package func makeAsyncIterator() -> Iterator {
        Iterator(self.fileDescriptor, ioQueue: ioQueue, readChunkSize: self.readChunkSize)
    }
}

package struct VirtualReadableFileStream: AsyncSequence {
    package typealias Element = [UInt8]

    package final class Iterator: AsyncIteratorProtocol {
        init(bytes: [UInt8]? = nil) {
            self.bytes = bytes
        }

        var bytes: [UInt8]?

        package func next() async throws -> [UInt8]? {
            defer { bytes = nil }

            return self.bytes
        }
    }

    let bytes: [UInt8]

    package func makeAsyncIterator() -> Iterator {
        Iterator(bytes: self.bytes)
    }
}
