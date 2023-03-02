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

import Foundation

import Crypto

typealias CryptoECPrivateKey = P256.Signing.PrivateKey
typealias CryptoECPublicKey = P256.Signing.PublicKey

struct ECPrivateKey: PrivateKey {
    let underlying: CryptoECPrivateKey

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let pem = String(decoding: data, as: UTF8.self)
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            self.underlying = try CryptoECPrivateKey(pemRepresentation: pem)
        } else {
            let pemDocument = try ASN1.PEMDocument(pemString: pem)
            let parsed = try ASN1.SEC1PrivateKey(asn1Encoded: Array(pemDocument.derBytes))
            self.underlying = try CryptoECPrivateKey(rawRepresentation: parsed.privateKey)
        }
        #else
        self.underlying = try CryptoECPrivateKey(pemRepresentation: pem)
        #endif
    }
}

struct ECPublicKey: PublicKey {
    let underlying: CryptoECPublicKey

    /// `data` should follow the ANSI X9.63 standard format
    init(data: Data) throws {
        self.underlying = try CryptoECPublicKey(x963Representation: data)
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let pem = String(decoding: data, as: UTF8.self)
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            self.underlying = try CryptoECPublicKey(pemRepresentation: pem)
        } else {
            let pemDocument = try ASN1.PEMDocument(pemString: pem)
            let parsed = try ASN1.SubjectPublicKeyInfo(asn1Encoded: Array(pemDocument.derBytes))
            self.underlying = try CryptoECPublicKey(x963Representation: parsed.key)
        }
        #else
        self.underlying = try CryptoECPublicKey(pemRepresentation: pem)
        #endif
    }
}
