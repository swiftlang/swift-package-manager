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

internal import SystemPackage
internal import class Dispatch.DispatchQueue

/// Type-erasure wrapper over underlying file system readable streams.
package enum ReadableFileStream: AsyncSequence {
    package typealias Element = ArraySlice<UInt8>

    case real(RealReadableFileStream)
    case mock(MockReadableFileStream)

    package enum Iterator: AsyncIteratorProtocol {
        case real(RealReadableFileStream.Iterator)
        case mock(MockReadableFileStream.Iterator)

        package func next() async throws -> ArraySlice<UInt8>? {
            switch self {
            case .real(let local):
                return try await local.next()
            case .mock(let virtual):
                return try await virtual.next()
            }
        }
    }

    package func makeAsyncIterator() -> Iterator {
        switch self {
        case .real(let real):
            return .real(real.makeAsyncIterator())
        case .mock(let mock):
            return .mock(mock.makeAsyncIterator())
        }
    }
}

/// A stream of file contents from the real file system provided by the OS.
package struct RealReadableFileStream: AsyncSequence {
    package typealias Element = ArraySlice<UInt8>

    let fileDescriptor: FileDescriptor
    let ioQueue: DispatchQueue
    let readChunkSize: Int

    package final class Iterator: AsyncIteratorProtocol {
        init(_ fileDescriptor: FileDescriptor, ioQueue: DispatchQueue, readChunkSize: Int) {
            self.fileDescriptor = fileDescriptor
            self.ioQueue = ioQueue
            self.chunkSize = readChunkSize
        }

        private let fileDescriptor: FileDescriptor
        private let ioQueue: DispatchQueue
        private let chunkSize: Int

        package func next() async throws -> ArraySlice<UInt8>? {
            let chunkSize = self.chunkSize
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
                return buffer[...]
            }
        }
    }

    package func makeAsyncIterator() -> Iterator {
        Iterator(self.fileDescriptor, ioQueue: ioQueue, readChunkSize: self.readChunkSize)
    }
}


/// A stream of file contents backed by an in-memory array of bytes.
package struct MockReadableFileStream: AsyncSequence {
    package typealias Element = ArraySlice<UInt8>

    package final class Iterator: AsyncIteratorProtocol {
        init(bytes: [UInt8], chunkSize: Int) {
            self.bytes = bytes
            self.chunkSize = chunkSize
        }

        private let chunkSize: Int
        var bytes: [UInt8]
        private var position = 0

        package func next() async throws -> ArraySlice<UInt8>? {
            let nextPosition = Swift.min(bytes.count, position + chunkSize)

            guard nextPosition > position else {
                return nil
            }

            defer { self.position = nextPosition }
            return self.bytes[position..<nextPosition]
        }
    }

    let bytes: [UInt8]
    let chunkSize: Int

    package func makeAsyncIterator() -> Iterator {
        Iterator(bytes: self.bytes, chunkSize: self.chunkSize)
    }
}
