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
        fixture(name: "Collections") { directoryPath in
            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let base64EncodedCert = Data(try localFileSystem.readFileContents(certPath).contents).base64EncodedString()
            let header = Signature.Header(algorithm: .RS256, certChain: [base64EncodedCert])

            let privateKeyPath = directoryPath.appending(components: "Signing", "Test_rsa_key.pem")
            let privateKey = try RSAPrivateKey(pem: readPEM(path: privateKeyPath))

            let signature = try Signature.generate(for: payload, with: header, using: privateKey)

            let parser = try Signature.Parser(signature)
            XCTAssertEqual(payload, try parser.payload(as: [String: String].self))
            XCTAssertEqual(header, try parser.header())

            // Extract public key from the certificate in signature header
            let certData = Data(base64Encoded: try parser.header().certChain.first!)!
            let certificate = try Certificate(derEncoded: certData)
            let publicKey = try certificate.publicKey()

            // Verify signature using the public key
            XCTAssertNoThrow(try parser.validate(using: publicKey))
        }
    }

    func test_RS256_generateAndValidate_keyMismatch() throws {
        fixture(name: "Collections") { directoryPath in
            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let base64EncodedCert = Data(try localFileSystem.readFileContents(certPath).contents).base64EncodedString()
            let header = Signature.Header(algorithm: .RS256, certChain: [base64EncodedCert])

            let privateKeyPath = directoryPath.appending(components: "Signing", "rsa_private.pem")
            let privateKey = try RSAPrivateKey(pem: readPEM(path: privateKeyPath))

            let signature = try Signature.generate(for: payload, with: header, using: privateKey)

            let parser = try Signature.Parser(signature)
            XCTAssertEqual(payload, try parser.payload(as: [String: String].self))
            XCTAssertEqual(header, try parser.header())

            // Extract public key from the certificate in signature header
            let certData = Data(base64Encoded: try parser.header().certChain.first!)!
            let certificate = try Certificate(derEncoded: certData)
            let publicKey = try certificate.publicKey()

            // Verify signature using the public key
            XCTAssertThrowsError(try parser.validate(using: publicKey)) { error in
                guard SignatureError.invalidSignature == error as? SignatureError else {
                    return XCTFail("Expected SignatureError.invalidSignature")
                }
            }
        }
    }

    func test_ES256_generateAndValidate_happyCase() throws {
        fixture(name: "Collections") { directoryPath in
            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let base64EncodedCert = Data(try localFileSystem.readFileContents(certPath).contents).base64EncodedString()
            let header = Signature.Header(algorithm: .ES256, certChain: [base64EncodedCert])

            let privateKeyPath = directoryPath.appending(components: "Signing", "Test_ec_key.pem")
            let privateKey = try ECPrivateKey(pem: readPEM(path: privateKeyPath))

            let signature = try Signature.generate(for: payload, with: header, using: privateKey)

            let parser = try Signature.Parser(signature)
            XCTAssertEqual(payload, try parser.payload(as: [String: String].self))
            XCTAssertEqual(header, try parser.header())

            // Extract public key from the certificate in signature header
            let certData = Data(base64Encoded: try parser.header().certChain.first!)!
            let certificate = try Certificate(derEncoded: certData)
            let publicKey = try certificate.publicKey()

            // Verify signature using the public key
            XCTAssertNoThrow(try parser.validate(using: publicKey))
        }
    }

    func test_ES256_generateAndValidate_keyMismatch() throws {
        fixture(name: "Collections") { directoryPath in
            let payload = ["foo": "bar"]

            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let base64EncodedCert = Data(try localFileSystem.readFileContents(certPath).contents).base64EncodedString()
            let header = Signature.Header(algorithm: .ES256, certChain: [base64EncodedCert])

            let privateKeyPath = directoryPath.appending(components: "Signing", "ec_private.pem")
            let privateKey = try ECPrivateKey(pem: readPEM(path: privateKeyPath))

            let signature = try Signature.generate(for: payload, with: header, using: privateKey)

            let parser = try Signature.Parser(signature)
            XCTAssertEqual(payload, try parser.payload(as: [String: String].self))
            XCTAssertEqual(header, try parser.header())

            // Extract public key from the certificate in signature header
            let certData = Data(base64Encoded: try parser.header().certChain.first!)!
            let certificate = try Certificate(derEncoded: certData)
            let publicKey = try certificate.publicKey()

            // Verify signature using the public key
            XCTAssertThrowsError(try parser.validate(using: publicKey)) { error in
                guard SignatureError.invalidSignature == error as? SignatureError else {
                    return XCTFail("Expected SignatureError.invalidSignature")
                }
            }
        }
    }
}
