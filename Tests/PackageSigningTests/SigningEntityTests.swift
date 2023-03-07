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

import XCTest

import Basics
@testable import PackageSigning
import SPMTestSupport
import X509

final class SigningEntityTests: XCTestCase {
    func testFromECKeyCertificate() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_ec.cer"
            )
            let certificate = try Certificate(certificateBytes)

            let signingEntity = SigningEntity(certificate: certificate)
            XCTAssertNil(signingEntity.type)
            XCTAssertEqual(signingEntity.name, certificate.subject.commonName)
            XCTAssertEqual(signingEntity.organizationalUnit, certificate.subject.organizationalUnitName)
            XCTAssertEqual(signingEntity.organization, certificate.subject.organizationName)
        }
    }

    func testFromRSAKeyCertificate() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_rsa.cer"
            )
            let certificate = try Certificate(certificateBytes)

            let signingEntity = SigningEntity(certificate: certificate)
            XCTAssertNil(signingEntity.type)
            XCTAssertEqual(signingEntity.name, certificate.subject.commonName)
            XCTAssertEqual(signingEntity.organizationalUnit, certificate.subject.organizationalUnitName)
            XCTAssertEqual(signingEntity.organization, certificate.subject.organizationName)
        }
    }

    func testFromKeychainCertificate() async throws {
        #if canImport(Darwin)
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif
        #else
        throw XCTSkip("Skipping test on unsupported platform")
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = await identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let certificate = try Certificate(secIdentity: matches[0] as! SecIdentity)
        let signingEntity = SigningEntity(certificate: certificate)
        XCTAssertEqual(signingEntity.name, certificate.subject.commonName)
        XCTAssertEqual(signingEntity.organizationalUnit, certificate.subject.organizationalUnitName)
        XCTAssertEqual(signingEntity.organization, certificate.subject.organizationName)
    }
}
