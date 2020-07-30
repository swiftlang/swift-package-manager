// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation


@usableFromInline
internal func char(forNibble value: UInt8) -> CChar {
    switch value {
    case 0 ..< 10:
        return CChar(UInt8(ascii: "0") + value)
    default:
        precondition(value < 16)
        return CChar(UInt8(ascii: "a") + value - 10)
    }
}

@usableFromInline
internal func nibble(forHexChar char: UInt8) -> UInt8? {
    switch char {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
        return char - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"):
        return 10 + char - UInt8(ascii: "a")
    case UInt8(ascii: "A")...UInt8(ascii: "F"):
        return 10 + char - UInt8(ascii: "a")
    default:
        return nil
    }
}

@inlinable
public func hexEncode<T: Collection>(_ bytes: T) -> [CChar] where T.Element == UInt8, T.Index == Int {
    var output = [CChar](repeating: 0, count: Int(bytes.count) * 2)
    for (i, byte) in bytes.enumerated() {
        output[i*2 + 0] = char(forNibble: (byte >> 4) & 0xF)
        output[i*2 + 1] = char(forNibble: (byte >> 0) & 0xF)
    }
    return output
}

@inlinable
public func hexEncode<T: Collection>(_ bytes: T) -> String where T.Element == UInt8, T.Index == Int {
    let chars = hexEncode(bytes) as [CChar]
    return String(tsc_fromUTF8: chars.map{ UInt8($0) })
}

extension String {
    /// Decode the string as a sequence of hex bytes (with no leading 0x prefix).
    @inlinable
    public func tsc_hexDecode() -> [UInt8]? {
        let utf8 = self.utf8
        let count = utf8.count
        let byteCount = count / 2
        if count != byteCount * 2 { return nil }

        var result = [UInt8](repeating: 0, count: byteCount)
        var seq = utf8.makeIterator()
        for i in 0 ..< byteCount {
            guard let hi = nibble(forHexChar: seq.next()!) else { return nil }
            guard let lo = nibble(forHexChar: seq.next()!) else { return nil }
            result[i] = (hi << 4) | lo
        }
        return result
    }
}
