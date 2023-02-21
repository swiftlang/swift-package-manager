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
import PackageSigning
import SPMTestSupport

final class SigningIdentityTests: XCTestCase {
    #if swift(>=5.5.2)
    func testSigningWithIdentityFromKeychain() async throws {
        #if os(macOS)
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

        let info = matches[0].info
        XCTAssertNotNil(info.commonName)
        XCTAssertNotNil(info.organization)
        XCTAssertNotNil(info.organizationalUnit)

        let signatureProvider = SignatureProvider()
        let content = "per aspera ad astra".data(using: .utf8)!
        let signingIdentity = matches[0]

        // This call will trigger OS prompt(s) for key access
        let signature = try await signatureProvider.sign(
            content,
            with: signingIdentity,
            in: .cms_1_0_0,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let status = try await signatureProvider.status(
            of: signature,
            for: content,
            in: .cms_1_0_0,
            observabilityScope: ObservabilitySystem.NOOP
        )
        XCTAssertEqual(status, SignatureStatus.valid)
    }
    #endif
}
