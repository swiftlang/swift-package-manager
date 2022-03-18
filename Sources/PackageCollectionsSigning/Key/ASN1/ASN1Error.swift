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

// Source: https://github.com/apple/swift-crypto/blob/main/Sources/Crypto/CryptoKitErrors.swift

/// Errors encountered when parsing ASN.1 formatted keys.
enum ASN1Error: Error {
    /// The ASN.1 tag for this field is invalid or unsupported.
    case invalidFieldIdentifier

    /// The ASN.1 tag for the parsed field does not match the required format.
    case unexpectedFieldType

    /// An invalid ASN.1 object identifier was encountered.
    case invalidObjectIdentifier

    /// The format of the parsed ASN.1 object does not match the format required for the data type
    /// being decoded.
    case invalidASN1Object

    /// An ASN.1 integer was decoded that does not use the minimum number of bytes for its encoding.
    case invalidASN1IntegerEncoding

    /// An ASN.1 field was truncated and could not be decoded.
    case truncatedASN1Field

    /// The encoding used for the field length is not supported.
    case unsupportedFieldLength

    /// It was not possible to parse a string as a PEM document.
    case invalidPEMDocument
}
