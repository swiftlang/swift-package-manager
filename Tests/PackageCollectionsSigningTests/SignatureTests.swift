/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

@testable import PackageCollectionsSigning
import SPMTestSupport
import TSCBasic

class SignatureTests: XCTestCase {
    func test_RS256_generateAndValidate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let certData = Data(try localFileSystem.readFileContents(certPath).contents)
            let base64EncodedCert = certData.base64EncodedString()
            let certificate = try Certificate(derEncoded: certData)

            let header = Signature.Header(algorithm: .RS256, certChain: [base64EncodedCert])
            let privateKey = try RSAPrivateKey(pem: certRSAPrivateKey.bytes)
            let signature = try Signature.generate(for: payload, with: header, using: privateKey, jsonEncoder: jsonEncoder)

            let parsedSignature = try tsc_await { callback in
                Signature.parse(signature, certChainValidate: { _, cb in cb(.success([certificate])) }, jsonDecoder: jsonDecoder, callback: callback)
            }
            XCTAssertEqual(payload, try jsonDecoder.decode([String: String].self, from: parsedSignature.payload))
            XCTAssertEqual(header, parsedSignature.header)
        }
    }

    func test_RS256_generateAndValidate_keyMismatch() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let certData = Data(try localFileSystem.readFileContents(certPath).contents)
            let base64EncodedCert = certData.base64EncodedString()
            let certificate = try Certificate(derEncoded: certData)

            let header = Signature.Header(algorithm: .RS256, certChain: [base64EncodedCert])
            // This is not cert's key so `parse` will fail
            let privateKey = try RSAPrivateKey(pem: rsaPrivateKey.bytes)
            let signature = try Signature.generate(for: payload, with: header, using: privateKey, jsonEncoder: jsonEncoder)

            XCTAssertThrowsError(try tsc_await { callback in
                Signature.parse(signature, certChainValidate: { _, cb in cb(.success([certificate])) }, jsonDecoder: jsonDecoder, callback: callback)
            }) { error in
                guard SignatureError.invalidSignature == error as? SignatureError else {
                    return XCTFail("Expected SignatureError.invalidSignature")
                }
            }
        }
    }

    func test_ES256_generateAndValidate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let certData = Data(try localFileSystem.readFileContents(certPath).contents)
            let base64EncodedCert = certData.base64EncodedString()
            let certificate = try Certificate(derEncoded: certData)

            let header = Signature.Header(algorithm: .ES256, certChain: [base64EncodedCert])
            let privateKey = try ECPrivateKey(pem: certECPrivateKey.bytes)
            let signature = try Signature.generate(for: payload, with: header, using: privateKey, jsonEncoder: jsonEncoder)

            let parsedSignature = try tsc_await { callback in
                Signature.parse(signature, certChainValidate: { _, cb in cb(.success([certificate])) }, jsonDecoder: jsonDecoder, callback: callback)
            }
            XCTAssertEqual(payload, try jsonDecoder.decode([String: String].self, from: parsedSignature.payload))
            XCTAssertEqual(header, parsedSignature.header)
        }
    }

    func test_ES256_generateAndValidate_keyMismatch() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder()
            let jsonDecoder = JSONDecoder()

            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let certData = Data(try localFileSystem.readFileContents(certPath).contents)
            let base64EncodedCert = certData.base64EncodedString()
            let certificate = try Certificate(derEncoded: certData)

            let header = Signature.Header(algorithm: .ES256, certChain: [base64EncodedCert])
            // This is not cert's key so `parse` will fail
            let privateKey = try ECPrivateKey(pem: ecPrivateKey.bytes)
            let signature = try Signature.generate(for: payload, with: header, using: privateKey, jsonEncoder: jsonEncoder)

            XCTAssertThrowsError(try tsc_await { callback in
                Signature.parse(signature, certChainValidate: { _, cb in cb(.success([certificate])) }, jsonDecoder: jsonDecoder, callback: callback)
            }) { error in
                guard SignatureError.invalidSignature == error as? SignatureError else {
                    return XCTFail("Expected SignatureError.invalidSignature")
                }
            }
        }
    }
}
