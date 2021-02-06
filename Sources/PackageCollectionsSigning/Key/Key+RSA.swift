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
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Security
#else
@_implementationOnly import CCryptoBoringSSL
#endif

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
typealias RSAPublicKey = CoreRSAPublicKey
typealias RSAPrivateKey = CoreRSAPrivateKey
#else
typealias RSAPublicKey = BoringSSLRSAPublicKey
typealias RSAPrivateKey = BoringSSLRSAPrivateKey
#endif

// MARK: - RSA key implementations using the Security framework

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
struct CoreRSAPrivateKey: PrivateKey {
    let underlying: SecKey

    init(pem: String) throws {
        let data = try KeyUtilities.stripHeaderAndFooter(pem: pem)

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

    init(pem: String) throws {
        let data = try KeyUtilities.stripHeaderAndFooter(pem: pem)
        try self.init(data: data)
    }
}

// MARK: - RSA key implementations using BoringSSL

// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/RSA/RSAKey.swift

#else
final class BoringSSLRSAPrivateKey: PrivateKey, BoringSSLKey {
    let underlying: UnsafeMutablePointer<CCryptoBoringSSL.RSA>
    let algorithm: OpaquePointer = CCryptoBoringSSL_EVP_sha256()

    deinit {
        CCryptoBoringSSL_RSA_free(self.underlying)
    }

    init(pem: String) throws {
        guard let data = pem.data(using: .utf8) else {
            throw KeyError.invalidPEM
        }

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
    let algorithm: OpaquePointer = CCryptoBoringSSL_EVP_sha256()

    deinit {
        CCryptoBoringSSL_RSA_free(self.underlying)
    }

    /// `data` should be in the PKCS #1 format
    init(data: Data) throws {
        var bytes: UnsafePointer<UInt8>? = try data.withUnsafeBytes {
            guard let bytes = $0.bindMemory(to: UInt8.self).baseAddress else {
                throw KeyError.invalidData
            }
            return bytes
        }

        guard let key = CCryptoBoringSSL_d2i_PublicKey(EVP_PKEY_RSA, nil, &bytes, numericCast(data.count)) else {
            throw BoringSSLKeyError.failedToLoadKeyFromBytes
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }

        guard let pointer = CCryptoBoringSSL_EVP_PKEY_get1_RSA(key) else {
            throw BoringSSLKeyError.rsaConversionFailure
        }

        self.underlying = pointer
    }

    init(pem: String) throws {
        guard let data = pem.data(using: .utf8) else {
            throw KeyError.invalidPEM
        }

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
#endif
