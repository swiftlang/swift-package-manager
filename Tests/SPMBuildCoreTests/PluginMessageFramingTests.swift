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

// The 8-byte little-endian length header the wire format uses, built independently of `framed`.
private func leHeader(_ value: UInt64) -> [UInt8] {
    (0 ..< 8).map { UInt8((value >> (UInt64($0) * 8)) & 0xFF) }
}

@Suite
struct PluginMessageFramingTests {
    @Test func framedProducesHeaderThenPayload() {
        let message = Data("hello plugin".utf8)
        #expect(framed(message) == leHeader(UInt64(message.count)) + Array(message))
    }

    @Test func framedEmptyPayloadIsAnEightByteHeader() {
        #expect(framed(Data()) == leHeader(0))
    }

    @Test func reassemblesTwoFramesFromOneChunk() throws {
        var reassembler = FrameReassembler()
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let frames = try reassembler.push(framed(first) + framed(second))
        #expect(frames == [first, second])
        try reassembler.finish()
    }

    @Test func reassemblesHeaderSplitAcrossChunks() throws {
        var reassembler = FrameReassembler()
        let message = Data("payload".utf8)
        let bytes = framed(message)
        #expect(try reassembler.push(Array(bytes[0 ..< 4])).isEmpty)
        #expect(try reassembler.push(Array(bytes[4...])) == [message])
        try reassembler.finish()
    }

    @Test func reassemblesPayloadSplitAcrossChunks() throws {
        var reassembler = FrameReassembler()
        let message = Data("0123456789".utf8)
        let bytes = framed(message)
        // Header plus two payload bytes: not yet a whole frame.
        #expect(try reassembler.push(Array(bytes[0 ..< 10])).isEmpty)
        #expect(try reassembler.push(Array(bytes[10...])) == [message])
        try reassembler.finish()
    }

    @Test func trailingPartialFrameYieldsNothingAndFinishThrows() throws {
        var reassembler = FrameReassembler()
        let complete = Data("complete".utf8)
        let nextFrame = framed(Data("tail".utf8))
        let frames = try reassembler.push(framed(complete) + Array(nextFrame[0 ..< 3]))
        #expect(frames == [complete])
        #expect(throws: PluginMessageFramingError.self) { try reassembler.finish() }
    }

    @Test func declaredLengthBelowTwoThrows() {
        var reassembler = FrameReassembler()
        #expect(throws: PluginMessageFramingError.self) { _ = try reassembler.push(leHeader(1)) }
    }

    @Test func declaredLengthAboveIntMaxThrows() {
        var reassembler = FrameReassembler()
        #expect(throws: PluginMessageFramingError.self) {
            _ = try reassembler.push(leHeader(UInt64(Int.max) + 1))
        }
    }

    @Test func finishThrowsOnPartialHeader() throws {
        var reassembler = FrameReassembler()
        _ = try reassembler.push([0x01, 0x02, 0x03])
        #expect(throws: PluginMessageFramingError.self) { try reassembler.finish() }
    }
}
