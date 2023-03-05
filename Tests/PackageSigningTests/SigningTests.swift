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

import _CryptoExtras // for RSA
import Basics
import Crypto
@testable import PackageSigning
import SPMTestSupport
import func TSCBasic.tsc_await
import X509

#if swift(>=5.5.2)
final class SigningTests: XCTestCase {
    func testCMS1_0_0EndToEnd() async throws {
        let signingIdentity = try tsc_await { self.ecTestSigningIdentity(callback: $0) }
        let content = Array("per aspera ad astra".utf8)

        let signatureFormat = SignatureFormat.cms_1_0_0
        let signature = try await SignatureProvider.sign(
            content: content,
            identity: signingIdentity,
            format: signatureFormat,
            observabilityScope: ObservabilitySystem.NOOP
        )

        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

        let status = try await SignatureProvider.status(
            signature: signature,
            content: content,
            format: signatureFormat,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        XCTAssertEqual("Test (EC)", signingEntity.name)
        XCTAssertEqual("Test (EC)", signingEntity.organizationalUnit)
        XCTAssertEqual("Test (EC)", signingEntity.organization)
    }

    func testCMSEndToEndWithECSigningIdentity() async throws {
        let signingIdentity = try tsc_await { self.ecTestSigningIdentity(callback: $0) }
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)

        let signature = try await cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            observabilityScope: ObservabilitySystem.NOOP
        )

        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        XCTAssertEqual("Test (EC)", signingEntity.name)
        XCTAssertEqual("Test (EC)", signingEntity.organizationalUnit)
        XCTAssertEqual("Test (EC)", signingEntity.organization)
    }

    func testCMSEndToEndWithRSASigningIdentity() async throws {
        let signingIdentity = try tsc_await { self.rsaTestSigningIdentity(callback: $0) }
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)

        let signature = try await cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            observabilityScope: ObservabilitySystem.NOOP
        )

        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = try tsc_await { self.testRoots(callback: $0) }

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        XCTAssertEqual("Test (RSA)", signingEntity.name)
        XCTAssertEqual("Test (RSA)", signingEntity.organizationalUnit)
        XCTAssertEqual("Test (RSA)", signingEntity.organization)
    }

    func testCMSWrongKeyTypeForSignatureAlgorithm() async throws {
        let signingIdentity = try tsc_await { self.ecTestSigningIdentity(callback: $0) }
        let content = Array("per aspera ad astra".utf8)

        // Key is EC but signature algorithm is RSA
        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)

        do {
            _ = try await cmsProvider.sign(
                content: content,
                identity: signingIdentity,
                observabilityScope: ObservabilitySystem.NOOP
            )
            XCTFail("Expected error")
        } catch {
            guard case SigningError.keyDoesNotSupportSignatureAlgorithm = error else {
                return XCTFail("Expected SigningError.keyDoesNotSupportSignatureAlgorithm but got \(error)")
            }
        }
    }

    func testCMS1_0_0EndToEndWithSigningIdentityFromKeychain() async throws {
        #if os(macOS)
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif
        #else
        throw XCTSkip("Skipping test on unsupported platform")
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_EC_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_EC_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = await identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let signingIdentity = matches[0]
        let content = Array("per aspera ad astra".utf8)

        let signatureFormat = SignatureFormat.cms_1_0_0
        // This call will trigger OS prompt(s) for key access
        let signature = try await SignatureProvider.sign(
            content: content,
            identity: signingIdentity,
            format: signatureFormat,
            observabilityScope: ObservabilitySystem.NOOP
        )

        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = try tsc_await { self.wwdrRoots(callback: $0) }

        let status = try await SignatureProvider.status(
            signature: signature,
            content: content,
            format: signatureFormat,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        XCTAssertNotNil(signingEntity.name)
        XCTAssertNotNil(signingEntity.organizationalUnit)
        XCTAssertNotNil(signingEntity.organization)
    }

    func testCMSEndToEndWithRSASigningIdentityFromKeychain() async throws {
        #if os(macOS)
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif
        #else
        throw XCTSkip("Skipping test on unsupported platform")
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_RSA_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_RSA_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = await identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let signingIdentity = matches[0]
        let content = Array("per aspera ad astra".utf8)
        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)

        // This call will trigger OS prompt(s) for key access
        let signature = try await cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            observabilityScope: ObservabilitySystem.NOOP
        )

        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = try tsc_await { self.wwdrRoots(callback: $0) }

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        XCTAssertNotNil(signingEntity.name)
        XCTAssertNotNil(signingEntity.organizationalUnit)
        XCTAssertNotNil(signingEntity.organization)
    }

    func testCMSEndToEndWithECSigningIdentityFromKeychain() async throws {
        #if os(macOS)
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif
        #else
        throw XCTSkip("Skipping test on unsupported platform")
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_EC_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_EC_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = await identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let signingIdentity = matches[0]
        let content = Array("per aspera ad astra".utf8)
        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)

        // This call will trigger OS prompt(s) for key access
        let signature = try await cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            observabilityScope: ObservabilitySystem.NOOP
        )

        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = try tsc_await { self.wwdrRoots(callback: $0) }

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        XCTAssertNotNil(signingEntity.name)
        XCTAssertNotNil(signingEntity.organizationalUnit)
        XCTAssertNotNil(signingEntity.organization)
    }

    private func ecTestSigningIdentity(callback: (Result<SigningIdentity, Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let certificateBytes = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "Test_ec.cer"
                )
                let certificate = try Certificate(derEncoded: certificateBytes)

                let privateKeyBytes = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "Test_ec_key.p8"
                )
                let privateKey = try P256.Signing.PrivateKey(derRepresentation: privateKeyBytes)

                callback(.success(SwiftSigningIdentity(
                    certificate: certificate,
                    privateKey: Certificate.PrivateKey(privateKey)
                )))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func rsaTestSigningIdentity(callback: (Result<SigningIdentity, Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let certificateBytes = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "Test_rsa.cer"
                )
                let certificate = try Certificate(derEncoded: certificateBytes)

                let privateKeyBytes = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "Test_rsa_key.p8"
                )
                let privateKey = try _RSA.Signing.PrivateKey(derRepresentation: privateKeyBytes)

                callback(.success(SwiftSigningIdentity(
                    certificate: certificate,
                    privateKey: Certificate.PrivateKey(privateKey)
                )))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func testRoots(callback: (Result<[[UInt8]], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let intermediateCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "TestIntermediateCA.cer"
                )
                let rootCA = try readFileContents(in: fixturePath, pathComponents: "Certificates", "TestRootCA.cer")
                callback(.success([intermediateCA, rootCA]))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func wwdrRoots(callback: (Result<[[UInt8]], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let intermediateCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "AppleWWDRCAG3.cer"
                )
                let rootCA = try readFileContents(in: fixturePath, pathComponents: "Certificates", "AppleIncRoot.cer")
                callback(.success([intermediateCA, rootCA]))
            }
        } catch {
            callback(.failure(error))
        }
    }
}
#endif
