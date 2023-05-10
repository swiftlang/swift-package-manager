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

import _CryptoExtras
import Basics
import Crypto
import Foundation
@testable import PackageCollectionsSigning
import SPMTestSupport
import X509
import XCTest

class SignatureTests: XCTestCase {
    func test_RS256_generateAndValidate_happyCase() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = fixturePath.appending(components: "Certificates", "Test_rsa.cer")
            let certData: Data = try localFileSystem.readFileContents(certPath)
            let certBase64Encoded = certData.base64EncodedString()
            let certificate = try Certificate(derEncoded: Array(certData))

            let privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: certRSAPrivateKey)
            let signature = try Signature.generate(
                payload: payload,
                certChainData: [certData],
                jsonEncoder: jsonEncoder,
                signatureAlgorithm: .RS256
            ) {
                try privateKey.signature(for: SHA256.hash(data: $0), padding: Signature.rsaSigningPadding).rawRepresentation
            }

            let parsedSignature = try temp_await { callback in
                Signature.parse(
                    signature,
                    certChainValidate: { _, cb in cb(.success([certificate])) },
                    jsonDecoder: jsonDecoder,
                    callback: callback
                )
            }
            XCTAssertEqual(try jsonDecoder.decode([String: String].self, from: parsedSignature.payload), payload)
            XCTAssertEqual(parsedSignature.header.algorithm, Signature.Algorithm.RS256)
            XCTAssertEqual(parsedSignature.header.certChain, [certBase64Encoded])
        }
    }

    func test_RS256_generateAndValidate_keyMismatch() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = fixturePath.appending(components: "Certificates", "Test_rsa.cer")
            let certData: Data = try localFileSystem.readFileContents(certPath)
            let certificate = try Certificate(derEncoded: Array(certData))

            // This is not cert's key so `parse` will fail
            let privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: rsaPrivateKey)
            let signature = try Signature.generate(
                payload: payload,
                certChainData: [certData],
                jsonEncoder: jsonEncoder,
                signatureAlgorithm: .RS256
            ) {
                try privateKey.signature(for: SHA256.hash(data: $0), padding: Signature.rsaSigningPadding).rawRepresentation
            }

            XCTAssertThrowsError(try temp_await { callback in
                Signature.parse(
                    signature,
                    certChainValidate: { _, cb in cb(.success([certificate])) },
                    jsonDecoder: jsonDecoder,
                    callback: callback
                )
            }) { error in
                guard SignatureError.invalidSignature == error as? SignatureError else {
                    return XCTFail("Expected SignatureError.invalidSignature")
                }
            }
        }
    }

    func test_ES256_generateAndValidate_happyCase() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = fixturePath.appending(components: "Certificates", "Test_ec.cer")
            let certData: Data = try localFileSystem.readFileContents(certPath)
            let certBase64Encoded = certData.base64EncodedString()
            let certificate = try Certificate(derEncoded: Array(certData))

            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: certECPrivateKey)
            let signature = try Signature.generate(
                payload: payload,
                certChainData: [certData],
                jsonEncoder: jsonEncoder,
                signatureAlgorithm: .ES256
            ) {
                try privateKey.signature(for: SHA256.hash(data: $0)).rawRepresentation
            }

            let parsedSignature = try temp_await { callback in
                Signature.parse(
                    signature,
                    certChainValidate: { _, cb in cb(.success([certificate])) },
                    jsonDecoder: jsonDecoder,
                    callback: callback
                )
            }
            XCTAssertEqual(try jsonDecoder.decode([String: String].self, from: parsedSignature.payload), payload)
            XCTAssertEqual(parsedSignature.header.algorithm, Signature.Algorithm.ES256)
            XCTAssertEqual(parsedSignature.header.certChain, [certBase64Encoded])
        }
    }

    func test_ES256_generateAndValidate_keyMismatch() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = fixturePath.appending(components: "Certificates", "Test_ec.cer")
            let certData: Data = try localFileSystem.readFileContents(certPath)
            let certificate = try Certificate(derEncoded: Array(certData))

            // This is not cert's key so `parse` will fail
            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: ecPrivateKey)
            let signature = try Signature.generate(
                payload: payload,
                certChainData: [certData],
                jsonEncoder: jsonEncoder,
                signatureAlgorithm: .ES256
            ) {
                try privateKey.signature(for: SHA256.hash(data: $0)).rawRepresentation
            }

            XCTAssertThrowsError(try temp_await { callback in
                Signature.parse(
                    signature,
                    certChainValidate: { _, cb in cb(.success([certificate])) },
                    jsonDecoder: jsonDecoder,
                    callback: callback
                )
            }) { error in
                guard SignatureError.invalidSignature == error as? SignatureError else {
                    return XCTFail("Expected SignatureError.invalidSignature")
                }
            }
        }
    }
}
