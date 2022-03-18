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

import struct Foundation.Data

#if os(macOS)
import Security
#elseif os(Linux) || os(Windows) || os(Android)
@_implementationOnly import CCryptoBoringSSL
#endif

// MARK: - MessageSigner and MessageValidator conformance using the Security framework

#if os(macOS)
extension CoreRSAPrivateKey {
    func sign(message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(self.underlying,
                                                    .rsaSignatureMessagePKCS1v15SHA256,
                                                    message as CFData,
                                                    &error) as Data? else {
            throw error.map { $0.takeRetainedValue() as Error } ?? SigningError.signFailure
        }
        return signature
    }
}

extension CoreRSAPublicKey {
    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        SecKeyVerifySignature(
            self.underlying,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            signature as CFData,
            nil // no-match is considered an error as well so we would rather not trap it
        )
    }
}

// MARK: - MessageSigner and MessageValidator conformance using BoringSSL

#elseif os(Linux) || os(Windows) || os(Android)
// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/RSA/RSASigner.swift
extension BoringSSLRSAPrivateKey: BoringSSLSigning {
    private static let algorithm = BoringSSLEVP(type: .sha256)

    var algorithm: BoringSSLEVP {
        Self.algorithm
    }

    func sign(message: Data) throws -> Data {
        let digest = try self.digest(message)

        var signatureLength: UInt32 = 0
        var signature = [UInt8](
            repeating: 0,
            count: Int(CCryptoBoringSSL_RSA_size(self.underlying))
        )

        guard CCryptoBoringSSL_RSA_sign(
            CCryptoBoringSSL_EVP_MD_type(self.algorithm.underlying),
            digest,
            numericCast(digest.count),
            &signature,
            &signatureLength,
            self.underlying
        ) == 1 else {
            throw SigningError.signFailure
        }

        return Data(signature[0 ..< numericCast(signatureLength)])
    }
}

extension BoringSSLRSAPublicKey: BoringSSLSigning {
    private static let algorithm = BoringSSLEVP(type: .sha256)

    var algorithm: BoringSSLEVP {
        Self.algorithm
    }

    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        let digest = try self.digest(message)
        let signature = signature.copyBytes()

        return CCryptoBoringSSL_RSA_verify(
            CCryptoBoringSSL_EVP_MD_type(self.algorithm.underlying),
            digest,
            numericCast(digest.count),
            signature,
            numericCast(signature.count),
            self.underlying
        ) == 1
    }
}

// MARK: - MessageSigner and MessageValidator conformance for unsupported platforms

#else
extension UnsupportedRSAPrivateKey {
    func sign(message: Data) throws -> Data {
        fatalError("Unsupported: \(#function)")
    }
}

extension UnsupportedRSAPublicKey {
    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        fatalError("Unsupported: \(#function)")
    }
}
#endif
