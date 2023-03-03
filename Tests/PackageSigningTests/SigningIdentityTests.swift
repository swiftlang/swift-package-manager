//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest

import _CryptoExtras // For RSA
import Basics
import Crypto
@testable import PackageSigning
import SPMTestSupport
import X509

final class SigningIdentityTests: XCTestCase {
    func testSwiftSigningIdentityWithECKey() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateData: Data = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_ec.cer"
            )
            let certificate = try Certificate(derEncoded: Array(certificateData))

            let subject = certificate.subject
            XCTAssertEqual("Test (EC)", subject.commonName)
            XCTAssertEqual("Test (EC)", subject.organizationalUnitName)
            XCTAssertEqual("Test (EC)", subject.organizationName)

            let privateKeyData: Data = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_ec_key.p8"
            )
            let privateKey = try P256.Signing.PrivateKey(derRepresentation: privateKeyData)
            _ = SwiftSigningIdentity(certificate: certificate, privateKey: Certificate.PrivateKey(privateKey))

            // Test public API
            XCTAssertNoThrow(
                try SwiftSigningIdentity(
                    derEncodedCertificate: certificateData,
                    derEncodedPrivateKey: privateKeyData,
                    privateKeyType: .p256
                )
            )
        }
    }

    func testSwiftSigningIdentityWithRSAKey() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateData: Data = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_rsa.cer"
            )
            let certificate = try Certificate(derEncoded: Array(certificateData))

            let subject = certificate.subject
            XCTAssertEqual("Test (RSA)", subject.commonName)
            XCTAssertEqual("Test (RSA)", subject.organizationalUnitName)
            XCTAssertEqual("Test (RSA)", subject.organizationName)

            let privateKeyData: Data = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_rsa_key.p8"
            )
            let privateKey = try _RSA.Signing.PrivateKey(derRepresentation: privateKeyData)
            _ = SwiftSigningIdentity(certificate: certificate, privateKey: Certificate.PrivateKey(privateKey))
        }
    }

    func testSigningIdentityFromKeychain() async throws {
        #if canImport(Darwin)
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif
        #else
        throw XCTSkip("Skipping test on unsupported platform")
        #endif

        let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_LABEL"] ?? "<USER ID>"
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = try await identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let subject = try Certificate(secIdentity: matches[0] as! SecIdentity).subject
        XCTAssertNotNil(subject.commonName)
        XCTAssertNotNil(subject.organizationalUnitName)
        XCTAssertNotNil(subject.organizationName)
    }
}
