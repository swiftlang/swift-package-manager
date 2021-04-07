/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

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

#if os(macOS)
import Security
#elseif os(Linux) || os(Windows) || os(Android)
@_implementationOnly import CCryptoBoringSSL
#endif

#if os(macOS)
typealias RSAPublicKey = CoreRSAPublicKey
typealias RSAPrivateKey = CoreRSAPrivateKey
#elseif os(Linux) || os(Windows) || os(Android)
typealias RSAPublicKey = BoringSSLRSAPublicKey
typealias RSAPrivateKey = BoringSSLRSAPrivateKey
#else
typealias RSAPublicKey = UnsupportedRSAPublicKey
typealias RSAPrivateKey = UnsupportedRSAPrivateKey
#endif

// MARK: - RSA key implementations using the Security framework

#if os(macOS)
struct CoreRSAPrivateKey: PrivateKey {
    let underlying: SecKey

    var sizeInBits: Int {
        toBits(bytes: SecKeyGetBlockSize(self.underlying))
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let pemString = String(decoding: data, as: UTF8.self)
        let pemDocument = try ASN1.PEMDocument(pemString: pemString)
        let data = pemDocument.derBytes

        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData,
                                             options as CFDictionary,
                                             &error) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? KeyError.initializationFailure
        }

        self.underlying = key
    }
}

struct CoreRSAPublicKey: PublicKey {
    let underlying: SecKey

    var sizeInBits: Int {
        toBits(bytes: SecKeyGetBlockSize(self.underlying))
    }

    /// `data` should be in PKCS #1 format
    init(data: Data) throws {
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData,
                                             options as CFDictionary,
                                             &error) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? KeyError.initializationFailure
        }

        self.underlying = key
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let pemString = String(decoding: data, as: UTF8.self)
        let pemDocument = try ASN1.PEMDocument(pemString: pemString)
        try self.init(data: pemDocument.derBytes)
    }
}

// MARK: - RSA key implementations using BoringSSL

// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/RSA/RSAKey.swift

#elseif os(Linux) || os(Windows) || os(Android)
final class BoringSSLRSAPrivateKey: PrivateKey, BoringSSLKey {
    let underlying: UnsafeMutablePointer<CCryptoBoringSSL.RSA>

    deinit {
        CCryptoBoringSSL_RSA_free(self.underlying)
    }

    var sizeInBits: Int {
        toBits(bytes: Int(CCryptoBoringSSL_RSA_size(self.underlying)))
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let key = try Self.load(pem: data) { bio in
            CCryptoBoringSSL_PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }

        guard let pointer = CCryptoBoringSSL_EVP_PKEY_get1_RSA(key) else {
            throw BoringSSLKeyError.rsaConversionFailure
        }

        self.underlying = pointer
    }
}

final class BoringSSLRSAPublicKey: PublicKey, BoringSSLKey {
    let underlying: UnsafeMutablePointer<CCryptoBoringSSL.RSA>

    deinit {
        CCryptoBoringSSL_RSA_free(self.underlying)
    }

    var sizeInBits: Int {
        toBits(bytes: Int(CCryptoBoringSSL_RSA_size(self.underlying)))
    }

    /// `data` should be in the PKCS #1 format
    init(data: Data) throws {
        let bytes = data.copyBytes()
        let key = try bytes.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<UInt8>) throws -> UnsafeMutablePointer<EVP_PKEY> in
            var pointer = ptr.baseAddress
            guard let key = CCryptoBoringSSL_d2i_PublicKey(EVP_PKEY_RSA, nil, &pointer, numericCast(data.count)) else {
                throw BoringSSLKeyError.failedToLoadKeyFromBytes
            }
            return key
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }

        guard let pointer = CCryptoBoringSSL_EVP_PKEY_get1_RSA(key) else {
            throw BoringSSLKeyError.rsaConversionFailure
        }

        self.underlying = pointer
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let key = try Self.load(pem: data) { bio in
            CCryptoBoringSSL_PEM_read_bio_PUBKEY(bio, nil, nil, nil)
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }

        guard let pointer = CCryptoBoringSSL_EVP_PKEY_get1_RSA(key) else {
            throw BoringSSLKeyError.rsaConversionFailure
        }

        self.underlying = pointer
    }
}

// MARK: - RSA key implementations for unsupported platforms

#else
struct UnsupportedRSAPrivateKey: PrivateKey {
    var sizeInBits: Int {
        fatalError("Unsupported")
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        fatalError("Unsupported: \(#function)")
    }
}

struct UnsupportedRSAPublicKey: PublicKey {
    var sizeInBits: Int {
        fatalError("Unsupported")
    }

    init(data: Data) throws {
        fatalError("Unsupported: \(#function)")
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        fatalError("Unsupported: \(#function)")
    }
}
#endif
