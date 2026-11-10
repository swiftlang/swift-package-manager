//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

internal struct SBOMIdentifier: Codable, Equatable, Hashable {
    internal let value: String

    internal init(value: String) {
        self.value = value
    }

    internal static func generate() -> SBOMIdentifier {
        SBOMIdentifier(value: "urn:uuid:\(UUID().uuidString.lowercased())")
    }

    internal static func generate(from seed: String) -> SBOMIdentifier {
        let hex = seed.sha256Checksum
        var chars = Array(hex.prefix(32))
        // Set UUID version 5 (name-based) at character offset 12
        chars[12] = "5"
        // Set RFC 4122 variant (10xx) at character offset 16
        if let byte8HighNibble = Int(String(chars[16]), radix: 16) {
            let variantNibble = (byte8HighNibble & 0x3) | 0x8
            chars[16] = Character(String(variantNibble, radix: 16))
        } else {
            chars[16] = "8"
        }
        let p1 = String(chars[0..<8])
        let p2 = String(chars[8..<12])
        let p3 = String(chars[12..<16])
        let p4 = String(chars[16..<20])
        let p5 = String(chars[20..<32])
        return SBOMIdentifier(value: "urn:uuid:\(p1)-\(p2)-\(p3)-\(p4)-\(p5)")
    }
}
