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

class CertificateTests: XCTestCase {
    func test_withRSAKey_fromDER() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let data = Data(try localFileSystem.readFileContents(path).contents)

            let certificate = try Certificate(derEncoded: data)

            let subject = try certificate.subject()
            XCTAssertNil(subject.userID)
            XCTAssertEqual("Signer Test (Developer)", subject.organization)
            XCTAssertEqual("Signer Test (Developer)", subject.organizationalUnit)
            XCTAssertEqual("Signer Test (Developer)", subject.commonName)

            let issuer = try certificate.issuer()
            XCTAssertNil(issuer.userID)
            XCTAssertEqual("Signer Test Intermediate CA", issuer.organization)
            XCTAssertEqual("Signer Test Intermediate CA", issuer.organizationalUnit)
            XCTAssertEqual("Signer Test Intermediate CA", issuer.commonName)
        }
    }

    func test_withECKey_fromDER() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let data = Data(try localFileSystem.readFileContents(path).contents)

            let certificate = try Certificate(derEncoded: data)

            let subject = try certificate.subject()
            XCTAssertNil(subject.userID)
            XCTAssertEqual("Signer Test (EC) (Developer)", subject.organization)
            XCTAssertEqual("Signer Test (EC) (Developer)", subject.organizationalUnit)
            XCTAssertEqual("Signer Test (EC) (Developer)", subject.commonName)

            let issuer = try certificate.issuer()
            XCTAssertNil(issuer.userID)
            XCTAssertEqual("Signer Test (EC) Intermediate CA", issuer.organization)
            XCTAssertEqual("Signer Test (EC) Intermediate CA", issuer.organizationalUnit)
            XCTAssertEqual("Signer Test (EC) Intermediate CA", issuer.commonName)
        }
    }
}
