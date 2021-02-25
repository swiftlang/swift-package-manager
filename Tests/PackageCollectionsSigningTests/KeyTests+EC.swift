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

class ECKeyTests: XCTestCase {
    func testPublicKeyFromCertificate() throws {
        try skipIfUnsupportedPlatform()

        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let data = Data(try localFileSystem.readFileContents(path).contents)

            let certificate = try Certificate(derEncoded: data)
            XCTAssertNoThrow(try certificate.publicKey())
        }
    }

    func testPublicKeyFromPEM() throws {
        try skipIfUnsupportedPlatform()

        XCTAssertNoThrow(try ECPublicKey(pem: ecPublicKey.bytes))
    }

    func testPrivateKeyFromPEM() throws {
        try skipIfUnsupportedPlatform()

        XCTAssertNoThrow(try ECPrivateKey(pem: ecPrivateKey.bytes))
    }
}
