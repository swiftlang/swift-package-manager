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

class RSAKeySigningTests: XCTestCase {
    func test_signAndValidate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        let privateKey = try RSAPrivateKey(pem: rsaPrivateKey.bytes)
        let publicKey = try RSAPublicKey(pem: rsaPublicKey.bytes)

        let message = try JSONEncoder().encode(["foo": "bar"])
        let signature = try privateKey.sign(message: message)
        XCTAssertTrue(try publicKey.isValidSignature(signature, for: message))
    }

    func test_signAndValidate_mismatch() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        let privateKey = try RSAPrivateKey(pem: rsaPrivateKey.bytes)
        let publicKey = try RSAPublicKey(pem: rsaPublicKey.bytes)

        let jsonEncoder = JSONEncoder()
        let message = try jsonEncoder.encode(["foo": "bar"])
        let otherMessage = try jsonEncoder.encode(["foo": "baz"])
        let signature = try privateKey.sign(message: message)
        XCTAssertFalse(try publicKey.isValidSignature(signature, for: otherMessage))
    }
}
