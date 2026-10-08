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

@testable
import Commands

import Testing

struct UTF8StreamDecoderTests {
    @Test
    func passesCompleteChunksThrough() {
        var decoder = UTF8StreamDecoder()
        #expect(decoder.decode(Array("héllo\n".utf8)) == "héllo\n")
        #expect(decoder.flush() == "")
    }

    @Test
    func joinsTwoByteCharacterSplitAcrossChunks() {
        var decoder = UTF8StreamDecoder()
        #expect(decoder.decode([0x61, 0xC2]) == "a")
        #expect(decoder.decode([0xB5, 0x0A]) == "µ\n")
    }

    @Test
    func joinsFourByteCharacterSplitAcrossThreeChunks() {
        var decoder = UTF8StreamDecoder()
        let emoji = Array("🙂".utf8)
        #expect(decoder.decode([emoji[0]]) == "")
        #expect(decoder.decode([emoji[1], emoji[2]]) == "")
        #expect(decoder.decode([emoji[3], 0x21]) == "🙂!")
    }

    @Test
    func replacesInvalidBytesInsteadOfDroppingTheChunk() {
        var decoder = UTF8StreamDecoder()
        #expect(decoder.decode([0x61, 0xFF, 0x62]) == "a\u{FFFD}b")
    }

    @Test
    func flushEmitsIncompleteTrailingSequence() {
        var decoder = UTF8StreamDecoder()
        #expect(decoder.decode([0x61, 0xE2, 0x9C]) == "a")
        #expect(decoder.flush() == "\u{FFFD}")
        #expect(decoder.flush() == "")
    }
}
