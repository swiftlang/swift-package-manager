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

import Basics
@testable import PackageSigning
import SPMTestSupport
import X509

final class SigningEntityTests: XCTestCase {
    func testFromECKeyCertificate() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateData: Data = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_ec.cer"
            )
            let certificate = try Certificate(derEncoded: Array(certificateData))

            let signingEntity = SigningEntity(certificate: certificate)
            XCTAssertNil(signingEntity.type)
            XCTAssertEqual("Test (EC)", signingEntity.name)
            XCTAssertEqual("Test (EC)", signingEntity.organizationalUnit)
            XCTAssertEqual("Test (EC)", signingEntity.organization)
        }
    }

    func testFromRSAKeyCertificate() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateData: Data = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                "Test_rsa.cer"
            )
            let certificate = try Certificate(derEncoded: Array(certificateData))

            let signingEntity = SigningEntity(certificate: certificate)
            XCTAssertNil(signingEntity.type)
            XCTAssertEqual("Test (RSA)", signingEntity.name)
            XCTAssertEqual("Test (RSA)", signingEntity.organizationalUnit)
            XCTAssertEqual("Test (RSA)", signingEntity.organization)
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

        let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_LABEL"] ?? "<USER ID>"
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = try await identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let certificate = try Certificate(secIdentity: matches[0] as! SecIdentity)
        let signingEntity = SigningEntity(certificate: certificate)
        XCTAssertNotNil(signingEntity.name)
        XCTAssertNotNil(signingEntity.organizationalUnit)
        XCTAssertNotNil(signingEntity.organization)
    }
}
