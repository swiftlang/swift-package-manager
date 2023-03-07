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
        let keyAndCertChain = try tsc_await { self.ecTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let signatureFormat = SignatureFormat.cms_1_0_0
        let signature = try await SignatureProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            format: signatureFormat,
            observabilityScope: ObservabilitySystem.NOOP
        )

        // FIXME: test cert chain is not considered valid on non-Darwin platforms
        #if canImport(Darwin)
        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = [keyAndCertChain.rootCertificate]

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
        #endif
    }

    func testCMSEndToEndWithECSigningIdentity() async throws {
        let keyAndCertChain = try tsc_await { self.ecTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)

        let signature = try await cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        // FIXME: test cert chain is not considered valid on non-Darwin platforms
        #if canImport(Darwin)
        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = [keyAndCertChain.rootCertificate]

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
        #endif
    }

    func testCMSEndToEndWithRSASigningIdentity() async throws {
        let keyAndCertChain = try tsc_await { self.rsaTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(_RSA.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)

        let signature = try await cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        // FIXME: test cert chain is not considered valid on non-Darwin platforms
        #if canImport(Darwin)
        var verifierConfiguration = VerifierConfiguration()
        verifierConfiguration.trustedRoots = [keyAndCertChain.rootCertificate]

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
        #endif
    }

    func testCMSWrongKeyTypeForSignatureAlgorithm() async throws {
        let keyAndCertChain = try tsc_await { self.ecTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        // Key is EC but signature algorithm is RSA
        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)

        do {
            _ = try await cmsProvider.sign(
                content: content,
                identity: signingIdentity,
                intermediateCertificates: keyAndCertChain.intermediateCertificates,
                observabilityScope: ObservabilitySystem.NOOP
            )
            XCTFail("Expected error")
        } catch {
            guard case SigningError.keyDoesNotSupportSignatureAlgorithm = error else {
                return XCTFail("Expected SigningError.keyDoesNotSupportSignatureAlgorithm but got \(error)")
            }
        }
    }

    #if canImport(Darwin)
    func testCMS1_0_0EndToEndWithSigningIdentityFromKeychain() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
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
            intermediateCertificates: try tsc_await { self.wwdrIntermediates(callback: $0) },
            // TODO: don't need to do this for WWDR certs
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
    #endif

    #if canImport(Darwin)
    func testCMSEndToEndWithECSigningIdentityFromKeychain() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
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
            intermediateCertificates: try tsc_await { self.wwdrIntermediates(callback: $0) },
            // TODO: don't need to do this for WWDR certs
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
    #endif

    #if canImport(Darwin)
    func testCMSEndToEndWithRSASigningIdentityFromKeychain() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
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
            intermediateCertificates: try tsc_await { self.wwdrIntermediates(callback: $0) },
            // TODO: don't need to do this for WWDR certs
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
    #endif

    private func ecTestKeyAndCertChain(callback: (Result<KeyAndCertChain, Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let privateKey = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_ec_key.p8"
                )
                let certificate = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_ec.cer"
                )
                let intermediateCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "TestIntermediateCA.cer"
                )
                let rootCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "TestRootCA.cer"
                )

                callback(.success(KeyAndCertChain(
                    privateKey: privateKey,
                    certificateChain: [certificate, intermediateCA, rootCA]
                )))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func rsaTestKeyAndCertChain(callback: (Result<KeyAndCertChain, Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let privateKey = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_rsa_key.p8"
                )
                let certificate = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_rsa.cer"
                )
                let intermediateCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "TestIntermediateCA.cer"
                )
                let rootCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "TestRootCA.cer"
                )

                callback(.success(KeyAndCertChain(
                    privateKey: privateKey,
                    certificateChain: [certificate, intermediateCA, rootCA]
                )))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func wwdrIntermediates(callback: (Result<[[UInt8]], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let intermediateCA = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates",
                    "AppleWWDRCAG3.cer"
                )
                callback(.success([intermediateCA]))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func wwdrRoots(callback: (Result<[[UInt8]], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let rootCA = try readFileContents(in: fixturePath, pathComponents: "Certificates", "AppleIncRoot.cer")
                callback(.success([rootCA]))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private struct KeyAndCertChain {
        let privateKey: [UInt8]
        let certificateChain: [[UInt8]]

        var leafCertificate: [UInt8] {
            self.certificateChain.first!
        }

        var intermediateCertificates: [[UInt8]] {
            guard self.certificateChain.count > 1 else {
                return []
            }
            return Array(self.certificateChain.dropLast(1)[1...])
        }

        var rootCertificate: [UInt8] {
            self.certificateChain.last!
        }
    }
}
#endif
