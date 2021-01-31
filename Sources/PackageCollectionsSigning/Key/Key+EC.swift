/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Crypto
import Foundation

typealias CryptoECPrivateKey = P256.Signing.PrivateKey
typealias CryptoECPublicKey = P256.Signing.PublicKey

struct ECPrivateKey: PrivateKey {
    let underlying: CryptoECPrivateKey

    init(pem: String) throws {
        // TODO: init(pemRepresentation:) is available on macOS 11.0+
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let data = try KeyUtilities.stripHeaderAndFooter(pem: pem)
        // From the output of `openssl pkey -in eckey.pem -text -noout`, the P256 private key is 32-byte long.
        // PEM format is 7-byte pre_string || 32-byte private key || 14-byte mid_string || 65-byte public key
        // See: https://stackoverflow.com/questions/48101258/how-to-convert-an-ecdsa-key-to-pem-format
        self.underlying = try CryptoECPrivateKey(rawRepresentation: data.dropFirst(7).prefix(32))
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

    init(pem: String) throws {
        // TODO: init(pemRepresentation:) is available on macOS 11.0+
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let data = try KeyUtilities.stripHeaderAndFooter(pem: pem)
        // The P256 public key is 65-byte long and there's PEM prefix
        self.underlying = try CryptoECPublicKey(x963Representation: data.suffix(65))
        #else
        self.underlying = try CryptoECPublicKey(pemRepresentation: pem)
        #endif
    }
}
