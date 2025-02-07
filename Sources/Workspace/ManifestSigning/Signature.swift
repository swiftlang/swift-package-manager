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

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import _CryptoExtras
@_implementationOnly import Crypto
@_implementationOnly import X509
#else
import _CryptoExtras
import Crypto
import X509
#endif

// The logic in this source file loosely follows https://www.rfc-editor.org/rfc/rfc7515.html
// for JSON Web Signature (JWS).

struct Signature {
    let header: Header
    let payload: Data
    let signature: Data
}

extension Signature {
    enum Algorithm: String, Codable {
        case RS256 // RSASSA-PKCS1-v1_5 using SHA-256
        case ES256 // ECDSA using P-256 and SHA-256
    }

    struct Header: Equatable, Codable {
        // https://www.rfc-editor.org/rfc/rfc7515.html#section-4.1.1
        let algorithm: Algorithm

        /// Base64 encoded certificate chain
        let certChain: [String]

        enum CodingKeys: String, CodingKey {
            case algorithm = "alg"
            case certChain = "x5c"
        }
    }
}

// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/JWTSerializer.swift
extension Signature {
    static let rsaSigningPadding = _RSA.Signing.Padding.insecurePKCS1v1_5

    static func generate(
        payload: some Encodable,
        certChainData: [Data],
        jsonEncoder: JSONEncoder,
        signatureAlgorithm: Signature.Algorithm,
        signatureProvider: @escaping (Data) throws -> Data
    ) throws -> Data {
        let header = Signature.Header(
            algorithm: signatureAlgorithm,
            certChain: certChainData.map { $0.base64EncodedString() }
        )
        let headerData = try jsonEncoder.encode(header)
        let encodedHeader = headerData.base64URLEncodedBytes()

        let payloadData = try jsonEncoder.encode(payload)
        let encodedPayload = payloadData.base64URLEncodedBytes()

        // https://www.rfc-editor.org/rfc/rfc7515.html#section-5.1
        // Signing input: BASE64URL(header) + '.' + BASE64URL(payload)
        let signatureData = try signatureProvider(encodedHeader + .period + encodedPayload)
        let encodedSignature = signatureData.base64URLEncodedBytes()

        // Result: header.payload.signature
        let bytes = encodedHeader
            + .period
            + encodedPayload
            + .period
            + encodedSignature
        return bytes
    }
}

// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/JWTParser.swift
extension Signature {
    typealias CertChainValidate = ([Data]) async throws -> [Certificate]

    static func parse(
        _ signature: String,
        certChainValidate: CertChainValidate,
        jsonDecoder: JSONDecoder
    ) async throws -> Signature {
        let bytes = Array(signature.utf8)
        return try await Self.parse(bytes, certChainValidate: certChainValidate, jsonDecoder: jsonDecoder)
    }

    static func parse(
        _ signature: some DataProtocol,
        certChainValidate: CertChainValidate,
        jsonDecoder: JSONDecoder
    ) async throws -> Signature {
        let parts = signature.copyBytes().split(separator: .period)
        guard parts.count == 3 else {
            throw SignatureError.malformedSignature
        }

        let encodedHeader = parts[0]
        let encodedPayload = parts[1]
        let encodedSignature = parts[2]

        guard let headerBytes = encodedHeader.base64URLDecodedBytes(),
              let header = try? jsonDecoder.decode(Header.self, from: headerBytes)
        else {
            throw SignatureError.malformedSignature
        }

        // Signature header contains the certificate and public key for verification
        let certChainData = header.certChain.compactMap { Data(base64Encoded: $0) }
        // Make sure we restore all certs successfully
        guard certChainData.count == header.certChain.count else {
            throw SignatureError.malformedSignature
        }

        let certChain = try await certChainValidate(certChainData)

        guard let payloadBytes = encodedPayload.base64URLDecodedBytes(),
              let signatureBytes = encodedSignature.base64URLDecodedBytes()
        else {
            throw SignatureError.malformedSignature
        }

        // Extract public key from the certificate
        let certificate = certChain.first! // !-safe because certChain is not empty at this point
        // Verify the key was used to generate the signature
        let message = Data(encodedHeader) + .period + Data(encodedPayload)
        let digest = SHA256.hash(data: message)

        switch header.algorithm {
        case .ES256:
            guard let publicKey = P256.Signing.PublicKey(certificate.publicKey) else {
                throw SignatureError.invalidPublicKey
            }
            guard try publicKey.isValidSignature(.init(rawRepresentation: signatureBytes), for: digest)
            else {
                throw SignatureError.invalidSignature
            }
        case .RS256:
            guard let publicKey = _RSA.Signing.PublicKey(certificate.publicKey) else {
                throw SignatureError.invalidPublicKey
            }
            guard publicKey.isValidSignature(
                .init(rawRepresentation: signatureBytes),
                for: digest,
                padding: .insecurePKCS1v1_5
            ) else {
                throw SignatureError.invalidSignature
            }
        }

        return Signature(header: header, payload: payloadBytes, signature: signatureBytes)
    }
}

enum SignatureError: Error {
    case malformedSignature
    case invalidSignature
    case invalidPublicKey
}
