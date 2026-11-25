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
import Testing

@testable import SPMBuildCore

struct PluginMessageDecoderTests {
    /// Pushes `bytes` into `decoder` and returns the messages decoded so far.
    private func push(_ decoder: inout PluginMessageDecoder, _ bytes: [UInt8]) throws -> [Data] {
        try bytes.withUnsafeBytes { try decoder.push($0) }
    }

    @Test
    func frameProducesLittleEndianLengthHeaderFollowedByPayload() {
        let framed = framePluginMessage(Data([0xAA, 0xBB, 0xCC]))
        #expect(framed.count == 8 + 3)
        // 64-bit little-endian length of 3.
        #expect(Array(framed[0..<8]) == [3, 0, 0, 0, 0, 0, 0, 0])
        #expect(Array(framed[8...]) == [0xAA, 0xBB, 0xCC])
    }

    @Test
    func decodesSingleMessageInOneChunk() throws {
        let payload = Data("hello".utf8)
        var decoder = PluginMessageDecoder()
        #expect(try push(&decoder, framePluginMessage(payload)) == [payload])
    }

    @Test
    func decodesMultipleMessagesInOneChunk() throws {
        let first = Data("first".utf8)
        let second = Data("second message".utf8)
        var decoder = PluginMessageDecoder()
        let decoded = try push(&decoder, framePluginMessage(first) + framePluginMessage(second))
        #expect(decoded == [first, second])
    }

    @Test
    func reassemblesMessageSplitAcrossChunks() throws {
        let payload = Data("a longer payload that we split in two".utf8)
        let framed = framePluginMessage(payload)
        let mid = framed.count / 2

        var decoder = PluginMessageDecoder()
        #expect(try push(&decoder, Array(framed[..<mid])).isEmpty)
        #expect(try push(&decoder, Array(framed[mid...])) == [payload])
    }

    @Test
    func reassemblesMessageWithHeaderSplitAcrossChunks() throws {
        let payload = Data("payload".utf8)
        let framed = framePluginMessage(payload)

        var decoder = PluginMessageDecoder()
        // Deliver fewer than the 8 header bytes first: nothing can be decoded yet.
        #expect(try push(&decoder, Array(framed[..<4])).isEmpty)
        #expect(try push(&decoder, Array(framed[4...])) == [payload])
    }

    @Test
    func yieldsCompleteMessageAndBuffersPartialTrailingMessage() throws {
        let first = Data("complete".utf8)
        let second = Data("incomplete-for-now".utf8)
        let framedSecond = framePluginMessage(second)

        var decoder = PluginMessageDecoder()
        // The first full message plus the leading bytes of the second.
        #expect(try push(&decoder, framePluginMessage(first) + Array(framedSecond[..<5])) == [first])
        // The remainder of the second message completes it.
        #expect(try push(&decoder, Array(framedSecond[5...])) == [second])
    }

    @Test
    func emptyChunkDecodesNothing() throws {
        var decoder = PluginMessageDecoder()
        #expect(try push(&decoder, []).isEmpty)
    }

    @Test
    func reassemblesMessageDeliveredOneByteAtATime() throws {
        let payload = Data("drip".utf8)
        let framed = framePluginMessage(payload)

        var decoder = PluginMessageDecoder()
        var decoded = [Data]()
        for byte in framed {
            decoded += try push(&decoder, [byte])
        }
        #expect(decoded == [payload])
    }

    @Test
    func roundTripPreservesArbitraryPayload() throws {
        let payload = Data((0..<512).map { UInt8($0 % 256) })
        var decoder = PluginMessageDecoder()
        #expect(try push(&decoder, framePluginMessage(payload)) == [payload])
    }

    @Test
    func rejectsPayloadSizeBelowMinimum() {
        for size in [UInt8(0), 1] {
            var decoder = PluginMessageDecoder()
            let header: [UInt8] = [size, 0, 0, 0, 0, 0, 0, 0]
            #expect(throws: PluginMessageDecoderError.self) { try push(&decoder, header) }
        }
    }

    @Test
    func rejectsPayloadSizeAboveMaximumWithoutTrapping() {
        // Sizes above Int.max would trap in `Int(length)`; sizes above the maximum would be buffered without bound.
        for size in [PluginMessageDecoder.maximumPayloadSize + 1, UInt64(Int.max), UInt64(Int.max) + 1, UInt64.max] {
            var decoder = PluginMessageDecoder()
            var header = [UInt8]()
            var littleEndian = size.littleEndian
            withUnsafeBytes(of: &littleEndian) { header.append(contentsOf: $0) }
            #expect(throws: PluginMessageDecoderError.self) { try push(&decoder, header) }
        }
    }

    @Test
    func keepsMessagesDecodedBeforeACorruptHeaderUsable() throws {
        var decoder = PluginMessageDecoder()
        let payload = Data("{}".utf8)
        #expect(try push(&decoder, framePluginMessage(payload)) == [payload])
        // The decoder is still in a consistent state after the first message.
        #expect(try push(&decoder, framePluginMessage(payload)) == [payload])
    }
}
