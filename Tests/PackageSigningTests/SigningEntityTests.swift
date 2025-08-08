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

import Basics
@testable import PackageSigning
import _InternalTestSupport
import X509

struct SigningEntityTests {
    @Test
    func twoADPSigningEntitiesAreEqualIfTeamIDEqual() {
        let adp1 = SigningEntity.recognized(
            type: .adp,
            name: "A. Appleseed",
            organizationalUnit: "SwiftPM Test Unit X",
            organization: "A"
        )
        let adp2 = SigningEntity.recognized(
            type: .adp,
            name: "B. Appleseed",
            organizationalUnit: "SwiftPM Test Unit X",
            organization: "B"
        )
        let adp3 = SigningEntity.recognized(
            type: .adp,
            name: "C. Appleseed",
            organizationalUnit: "SwiftPM Test Unit Y",
            organization: "C"
        )
        #expect(adp1 == adp2)  // Only team ID (org unit) needs to match
        #expect(adp1 != adp3)
    }

    @Test(
        "From certificate key",
        arguments: [
            (certificateFilename: "Test_ec.cer", id: "EC Key"),
            (certificateFilename: "Test_rsa.cer", id: "RSA Key"),
        ]
    )
    func fromCertificate(certificateFilename: String, id: String) throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certificateBytes = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates",
                certificateFilename
            )
            let certificate = try Certificate(certificateBytes)

            let signingEntity = SigningEntity.from(certificate: certificate)
            guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
                Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
                return
            }
            #expect(name == certificate.subject.commonName)
            #expect(organizationalUnit == certificate.subject.organizationalUnitName)
            #expect(organization == certificate.subject.organizationName)
        }
    }
}

final class SigningEntityXCTests: XCTestCase {
    #if os(macOS)
        func testFromKeychainCertificate() async throws {
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

            let certificate = try Certificate(secIdentity: matches[0] as! SecIdentity)
            let signingEntity = SigningEntity.from(certificate: certificate)
            switch signingEntity {
            case .recognized(_, let name, let organizationalUnit, let organization):
                XCTAssertEqual(name, certificate.subject.commonName)
                XCTAssertEqual(organizationalUnit, certificate.subject.organizationalUnitName)
                XCTAssertEqual(organization, certificate.subject.organizationName)
            case .unrecognized(let name, let organizationalUnit, let organization):
                XCTAssertEqual(name, certificate.subject.commonName)
                XCTAssertEqual(organizationalUnit, certificate.subject.organizationalUnitName)
                XCTAssertEqual(organization, certificate.subject.organizationName)
            }
        }
    #endif
}
