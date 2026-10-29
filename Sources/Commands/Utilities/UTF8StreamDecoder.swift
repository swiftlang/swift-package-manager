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

/// Decodes a stream of UTF-8 byte chunks, holding back a multi-byte character split across chunk boundaries.
struct UTF8StreamDecoder {
    private var pending: [UInt8] = []

    mutating func decode(_ bytes: [UInt8]) -> String {
        let all = self.pending + bytes
        let split = Self.incompleteSuffixStart(of: all)
        self.pending = Array(all[split...])
        return String(decoding: all[..<split], as: UTF8.self)
    }

    mutating func flush() -> String {
        defer { self.pending = [] }
        return String(decoding: self.pending, as: UTF8.self)
    }

    private static func incompleteSuffixStart(of bytes: [UInt8]) -> Int {
        let lastLead = bytes.indices.reversed().prefix(4).first { !UTF8.isContinuation(bytes[$0]) }
        guard let lastLead else { return bytes.endIndex }
        let expectedLength = switch bytes[lastLead] {
        case 0xC0...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF7: 4
        default: 1
        }
        return bytes.endIndex - lastLead < expectedLength ? lastLead : bytes.endIndex
    }
}
