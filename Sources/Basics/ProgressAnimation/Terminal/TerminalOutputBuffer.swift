//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A simple buffer to accumulate output bytes into.
///
/// This buffer never shrinks.
struct TerminalOutputBuffer {
    /// Initial buffer size of the data buffer.
    ///
    /// This buffer will grow if more space is needed.
    static let initialBufferSize = 1024

    /// The data buffer.
    private var buffer: [UInt8]
    private var availableBufferSize: Int {
        self.buffer.capacity - self.buffer.count
    }

    init() {
        self.buffer = []
        self.buffer.reserveCapacity(Self.initialBufferSize)
    }

    /// Clears the buffer maintaining current capacity.
    mutating func flush(_ body: (borrowing [UInt8]) -> ()) {
        body(self.buffer)
        self.buffer.removeAll(keepingCapacity: true)
    }

    /// Write a string as utf8 bytes to the buffer.
    mutating func write(_ string: String) {
        self.write(string.utf8)
    }

    /// Write a collection of bytes to the buffer.
    mutating func write(_ bytes: some Collection<UInt8>) {
        let byteCount = bytes.count
        self.buffer.reserveCapacity(byteCount + self.buffer.count)
        self.buffer.append(contentsOf: bytes)
    }
}
