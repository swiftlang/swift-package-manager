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

import Testing
import XCTest

import _CryptoExtras  // For RSA
import Basics
import Crypto
@testable import PackageSigning
import _InternalTestSupport
import X509

struct SigningIdentityTests {
    @Test
    func swiftSigningIdentityWithECKey() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_ec.cer"
            )
            let certificate = try Certificate(certificateBytes)

            let subject = certificate.subject
            #expect("Test (EC) leaf" == subject.commonName)
            #expect("Test (EC) org unit" == subject.organizationalUnitName)
            #expect("Test (EC) org" == subject.organizationName)

            let privateKeyBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_ec_key.p8"
            )
            let privateKey = try P256.Signing.PrivateKey(derRepresentation: privateKeyBytes)
            _ = SwiftSigningIdentity(certificate: certificate, privateKey: Certificate.PrivateKey(privateKey))

            // Test public API
            #expect(throws: Never.self) {

                try SwiftSigningIdentity(
                    derEncodedCertificate: certificateBytes,
                    derEncodedPrivateKey: privateKeyBytes,
                    privateKeyType: .p256
                )
            }
        }
    }

    @Test
    func swiftSigningIdentityWithRSAKey() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_rsa.cer"
            )
            let certificate = try Certificate(certificateBytes)

            let subject = certificate.subject
            #expect("Test (RSA) leaf" == subject.commonName)
            #expect("Test (RSA) org unit" == subject.organizationalUnitName)
            #expect("Test (RSA) org" == subject.organizationName)

            let privateKeyBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_rsa_key.p8"
            )
            let privateKey = try _RSA.Signing.PrivateKey(derRepresentation: privateKeyBytes)
            _ = SwiftSigningIdentity(certificate: certificate, privateKey: Certificate.PrivateKey(privateKey))
        }
    }
}
final class SigningIdentityXCTests: XCTestCase {

    #if os(macOS)
        func testSigningIdentityFromKeychain() async throws {
            #if ENABLE_REAL_SIGNING_IDENTITY_TEST
            #else
                try XCTSkipIf(true)
            #endif

            guard let label = Environment.current["REAL_SIGNING_IDENTITY_LABEL"] else {
                throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_LABEL' env var is not set")
            }
            let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
            let matches = identityStore.find(by: label)
            XCTAssertTrue(!matches.isEmpty)

            let subject = try Certificate(secIdentity: matches[0] as! SecIdentity).subject
            XCTAssertNotNil(subject.commonName)
            XCTAssertNotNil(subject.organizationalUnitName)
            XCTAssertNotNil(subject.organizationName)
        }
    #endif
}
