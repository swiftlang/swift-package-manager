//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCrypto open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftCrypto project authors
// Licensed under Apache License v2.0
//
// See http://swift.org/LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of SwiftCrypto project authors
//
//===----------------------------------------------------------------------===//

import Foundation

// Source: https://github.com/apple/swift-crypto/blob/main/Sources/Crypto/ASN1/Basic%20ASN1%20Types/ASN1OctetString.swift

extension ASN1 {
    /// An octet string is a representation of a string of octets.
    struct ASN1OctetString: ASN1Parseable {
        var bytes: ArraySlice<UInt8>

        init(asn1Encoded node: ASN1.ASN1Node) throws {
            guard node.identifier == .primitiveOctetString else {
                throw ASN1Error.unexpectedFieldType
            }

            guard case .primitive(let content) = node.content else {
                preconditionFailure("ASN.1 parser generated primitive node with constructed content")
            }

            self.bytes = content
        }
    }
}

extension ASN1.ASN1OctetString: Hashable {}

extension ASN1.ASN1OctetString: ContiguousBytes {
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try self.bytes.withUnsafeBytes(body)
    }
}
