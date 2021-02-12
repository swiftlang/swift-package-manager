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

        static func from(keyType: KeyType) -> Algorithm {
            switch keyType {
            case .RSA:
                return .RS256
            case .EC:
                return .ES256
            }
        }
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
    static func generate<Payload>(for payload: Payload,
                                  with header: Header,
                                  using signer: MessageSigner,
                                  jsonEncoder: JSONEncoder = JSONEncoder()) throws -> Data where Payload: Encodable {
        let headerData = try jsonEncoder.encode(header)
        let encodedHeader = headerData.base64URLEncodedBytes()

        let payloadData = try jsonEncoder.encode(payload)
        let encodedPayload = payloadData.base64URLEncodedBytes()

        // https://www.rfc-editor.org/rfc/rfc7515.html#section-5.1
        // Signing input: BASE64URL(header) + '.' + BASE64URL(payload)
        let signatureData = try signer.sign(message: encodedHeader + .period + encodedPayload)
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
    typealias CertChainValidate = ([Data], @escaping (Result<[Certificate], Error>) -> Void) -> Void

    static func parse(_ signature: String,
                      certChainValidate: CertChainValidate,
                      jsonDecoder: JSONDecoder = JSONDecoder(),
                      callback: @escaping (Result<Signature, Error>) -> Void) {
        let bytes = Array(signature.utf8)
        Self.parse(bytes, certChainValidate: certChainValidate, jsonDecoder: jsonDecoder, callback: callback)
    }

    static func parse<SignatureData>(_ signature: SignatureData,
                                     certChainValidate: CertChainValidate,
                                     jsonDecoder: JSONDecoder = JSONDecoder(),
                                     callback: @escaping (Result<Signature, Error>) -> Void) where SignatureData: DataProtocol {
        let parts = signature.copyBytes().split(separator: .period)
        guard parts.count == 3 else {
            return callback(.failure(SignatureError.malformedSignature))
        }

        let encodedHeader = parts[0]
        let encodedPayload = parts[1]
        let encodedSignature = parts[2]

        guard let headerBytes = encodedHeader.base64URLDecodedBytes(),
            let header = try? jsonDecoder.decode(Header.self, from: headerBytes) else {
            return callback(.failure(SignatureError.malformedSignature))
        }

        // Signature header contains the certificate and public key for verification
        let certChainData = header.certChain.compactMap { Data(base64Encoded: $0) }
        // Make sure we restore all certs successfully
        guard certChainData.count == header.certChain.count else {
            return callback(.failure(SignatureError.malformedSignature))
        }

        certChainValidate(certChainData) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let certChain):
                do {
                    // Extract public key from the certificate
                    let certificate = certChain.first! // !-safe because certChain is not empty at this point
                    let publicKey = try certificate.publicKey()

                    guard let payload = encodedPayload.base64URLDecodedBytes() else {
                        return callback(.failure(SignatureError.malformedSignature))
                    }
                    guard let signature = encodedSignature.base64URLDecodedBytes() else {
                        return callback(.failure(SignatureError.malformedSignature))
                    }

                    // Verify the key was used to generate the signature
                    let message: Data = Data(encodedHeader) + .period + Data(encodedPayload)
                    guard try publicKey.isValidSignature(signature, for: message) else {
                        return callback(.failure(SignatureError.invalidSignature))
                    }
                    callback(.success(Signature(header: header, payload: payload, signature: signature)))
                } catch {
                    callback(.failure(error))
                }
            }
        }
    }
}

enum SignatureError: Error {
    case malformedSignature
    case invalidSignature
}
