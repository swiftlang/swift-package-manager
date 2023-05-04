//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// This source file is part of the Vapor open source project
//
// Copyright (c) 2017-2020 Vapor project authors
// Licensed under MIT
//
// See LICENSE for license information
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Foundation

// Source: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/Utilities/Base64URL.swift

extension DataProtocol {
    func base64URLDecodedBytes() -> Data? {
        var data = Data(self)
        data.base64URLUnescape()
        return Data(base64Encoded: data)
    }

    func base64URLEncodedBytes() -> Data {
        var data = Data(self).base64EncodedData()
        data.base64URLEscape()
        return data
    }
}

extension Data {
    /// Converts base64-url encoded data to a base64 encoded data.
    ///
    /// https://tools.ietf.org/html/rfc4648#page-7
    mutating func base64URLUnescape() {
        for i in 0 ..< self.count {
            switch self[i] {
            case 0x2D: self[self.index(self.startIndex, offsetBy: i)] = 0x2B
            case 0x5F: self[self.index(self.startIndex, offsetBy: i)] = 0x2F
            default: break
            }
        }
        /// https://stackoverflow.com/questions/43499651/decode-base64url-to-base64-swift
        let padding = count % 4
        if padding > 0 {
            self += Data(repeating: 0x3D, count: 4 - padding)
        }
    }

    /// Converts base64 encoded data to a base64-url encoded data.
    ///
    /// https://tools.ietf.org/html/rfc4648#page-7
    mutating func base64URLEscape() {
        for i in 0 ..< self.count {
            switch self[i] {
            case 0x2B: self[self.index(self.startIndex, offsetBy: i)] = 0x2D
            case 0x2F: self[self.index(self.startIndex, offsetBy: i)] = 0x5F
            default: break
            }
        }
        self = split(separator: 0x3D).first ?? .init()
    }
}
