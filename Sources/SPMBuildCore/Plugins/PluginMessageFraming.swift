//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

// Length-prefix framing for the host<->plugin protocol: an 8-byte little-endian UInt64 payload length
// followed by exactly that many payload bytes.

enum PluginMessageFramingError: Error {
    case invalidPayloadSize   // a declared length < 2, which the protocol never emits
    case payloadTooLarge      // a declared length that would overflow Int
    case truncatedFrame
}

func framed(_ message: Data) -> [UInt8] {
    var length = UInt64(littleEndian: UInt64(message.count))
    var bytes = [UInt8]()
    bytes.reserveCapacity(8 + message.count)
    withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
    bytes.append(contentsOf: message)
    return bytes
}

/// Accumulates raw output bytes and yields whole length-delimited messages as they complete.
struct FrameReassembler {
    private var buffer: [UInt8] = []

    mutating func push(_ bytes: [UInt8]) throws -> [Data] {
        buffer.append(contentsOf: bytes)
        var frames: [Data] = []
        var offset = 0
        while buffer.count - offset >= 8 {
            var length: UInt64 = 0
            for i in 0 ..< 8 { length |= UInt64(buffer[offset + i]) << (UInt64(i) * 8) }
            guard length >= 2 else { throw PluginMessageFramingError.invalidPayloadSize }
            guard length <= UInt64(Int.max) else { throw PluginMessageFramingError.payloadTooLarge }
            let payloadCount = Int(length)
            guard buffer.count - offset - 8 >= payloadCount else { break }
            let start = offset + 8
            frames.append(Data(buffer[start ..< start + payloadCount]))
            offset = start + payloadCount
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return frames
    }

    func finish() throws {
        if !buffer.isEmpty { throw PluginMessageFramingError.truncatedFrame }
    }
}
