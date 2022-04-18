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

class RSAKeyTests: XCTestCase {
    func testPublicKeyFromCertificate() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let data: Data = try localFileSystem.readFileContents(path)

            let certificate = try Certificate(derEncoded: data)
            XCTAssertNoThrow(try certificate.publicKey())
        }
    }

    func testPublicKeyFromPEM() throws {
        try skipIfUnsupportedPlatform()

        XCTAssertNoThrow(try RSAPublicKey(pem: rsaPublicKey.bytes))
    }

    func testPrivateKeyFromPEM() throws {
        try skipIfUnsupportedPlatform()

        XCTAssertNoThrow(try RSAPrivateKey(pem: rsaPrivateKey.bytes))
    }
}
