//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest

@testable import PackageCollectionsSigning
import SPMTestSupport
import TSCBasic

class CertificateTests: XCTestCase {
    func test_withRSAKey_fromDER() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let data: Data = try localFileSystem.readFileContents(path)

            let certificate = try Certificate(derEncoded: data)

            let subject = try certificate.subject()
            XCTAssertNil(subject.userID)
            XCTAssertEqual("Test (RSA)", subject.organization)
            XCTAssertEqual("Test (RSA)", subject.organizationalUnit)
            XCTAssertEqual("Test (RSA)", subject.commonName)

            let issuer = try certificate.issuer()
            XCTAssertNil(issuer.userID)
            XCTAssertEqual("Test Intermediate CA", issuer.organization)
            XCTAssertEqual("Test Intermediate CA", issuer.organizationalUnit)
            XCTAssertEqual("Test Intermediate CA", issuer.commonName)
        }
    }

    func test_withECKey_fromDER() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "Signing", "Test_ec.cer")
            let data: Data = try localFileSystem.readFileContents(path)

            let certificate = try Certificate(derEncoded: data)

            let subject = try certificate.subject()
            XCTAssertNil(subject.userID)
            XCTAssertEqual("Test (EC)", subject.organization)
            XCTAssertEqual("Test (EC)", subject.organizationalUnit)
            XCTAssertEqual("Test (EC)", subject.commonName)

            let issuer = try certificate.issuer()
            XCTAssertNil(issuer.userID)
            XCTAssertEqual("Test Intermediate CA", issuer.organization)
            XCTAssertEqual("Test Intermediate CA", issuer.organizationalUnit)
            XCTAssertEqual("Test Intermediate CA", issuer.commonName)
        }
    }
}
