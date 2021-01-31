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
    static func generate<Payload>(for payload: Payload,
                                  with header: Header,
                                  using signer: MessageSigner,
                                  jsonEncoder: JSONEncoder = JSONEncoder()) throws -> [UInt8] where Payload: Encodable {
        let headerData = try jsonEncoder.encode(header)
        let encodedHeader = headerData.base64URLEncodedBytes()

        let payloadData = try jsonEncoder.encode(payload)
        let encodedPayload = payloadData.base64URLEncodedBytes()

        // https://www.rfc-editor.org/rfc/rfc7515.html#section-5.1
        // Signing input: BASE64URL(header) + '.' + BASE64URL(payload)
        let signatureData = try signer.sign(message: Data(encodedHeader + [.period] + encodedPayload))
        let encodedSignature = signatureData.base64URLEncodedBytes()

        // Result: header.payload.signature
        let bytes = encodedHeader
            + [.period]
            + encodedPayload
            + [.period]
            + encodedSignature
        return bytes
    }
}

// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/JWTParser.swift
extension Signature {
    struct Parser {
        private let encodedHeader: ArraySlice<UInt8>
        private let encodedPayload: ArraySlice<UInt8>
        private let encodedSignature: ArraySlice<UInt8>

        private let jsonDecoder: JSONDecoder

        var payload: [UInt8] {
            self.encodedPayload.base64URLDecodedBytes()
        }

        var message: [UInt8] {
            Array(self.encodedHeader + [.period] + self.encodedPayload)
        }

        var signature: [UInt8] {
            self.encodedSignature.base64URLDecodedBytes()
        }

        init(_ signature: String, jsonDecoder: JSONDecoder = JSONDecoder()) throws {
            let bytes = Array(signature.utf8)
            try self.init(bytes, jsonDecoder: jsonDecoder)
        }

        init(_ signature: [UInt8], jsonDecoder: JSONDecoder = JSONDecoder()) throws {
            let parts = signature.copyBytes().split(separator: .period)

            guard parts.count == 3 else {
                throw SignatureError.malformedSignature
            }

            self.encodedHeader = parts[0]
            self.encodedPayload = parts[1]
            self.encodedSignature = parts[2]
            self.jsonDecoder = jsonDecoder
        }

        func header() throws -> Header {
            try self.jsonDecoder.decode(
                Header.self,
                from: Data(self.encodedHeader.base64URLDecodedBytes())
            )
        }

        func payload<Payload>(as payload: Payload.Type) throws -> Payload where Payload: Decodable {
            try self.jsonDecoder.decode(
                Payload.self,
                from: Data(self.encodedPayload.base64URLDecodedBytes())
            )
        }

        func validate(using validator: MessageValidator) throws {
            guard try validator.isValidSignature(Data(self.signature), for: Data(self.message)) else {
                throw SignatureError.invalidSignature
            }
        }
    }
}

enum SignatureError: Error {
    case malformedSignature
    case invalidSignature
}
