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

import _CryptoExtras // for RSA
import Basics
import Crypto
@testable import PackageSigning
import SPMTestSupport
import SwiftASN1
import func TSCBasic.tsc_await
@testable import X509 // need internal APIs for OCSP testing

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
        let signature = try SignatureProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            format: signatureFormat,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

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
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            return XCTFail("Expected SigningEntity.unrecognized but got \(signingEntity)")
        }
        XCTAssertEqual("Test (EC)", name)
        XCTAssertEqual("Test (EC)", organizationalUnit)
        XCTAssertEqual("Test (EC)", organization)
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
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            return XCTFail("Expected SigningEntity.unrecognized but got \(signingEntity)")
        }
        XCTAssertEqual("Test (EC)", name)
        XCTAssertEqual("Test (EC)", organizationalUnit)
        XCTAssertEqual("Test (EC)", organization)
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
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            return XCTFail("Expected SigningEntity.unrecognized but got \(signingEntity)")
        }
        XCTAssertEqual("Test (RSA)", name)
        XCTAssertEqual("Test (RSA)", organizationalUnit)
        XCTAssertEqual("Test (RSA)", organization)
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
            _ = try cmsProvider.sign(
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

    func testCMS1_0_0EndToEndWithSelfSignedCertificate() async throws {
        let keyAndCertChain = try tsc_await { self.ecSelfSignedTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let signatureFormat = SignatureFormat.cms_1_0_0
        let signature = try SignatureProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            format: signatureFormat,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

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
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            return XCTFail("Expected SigningEntity.unrecognized but got \(signingEntity)")
        }
        XCTAssertEqual("Test (EC)", name)
        XCTAssertEqual("Test (EC) org unit", organizationalUnit)
        XCTAssertEqual("Test (EC) org", organization)
    }

    func testCMSEndToEndWithSelfSignedECSigningIdentity() async throws {
        let keyAndCertChain = try tsc_await { self.ecSelfSignedTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            return XCTFail("Expected SigningEntity.unrecognized but got \(signingEntity)")
        }
        XCTAssertEqual("Test (EC)", name)
        XCTAssertEqual("Test (EC) org unit", organizationalUnit)
        XCTAssertEqual("Test (EC) org", organization)
    }

    func testCMSEndToEndWithSelfSignedRSASigningIdentity() async throws {
        let keyAndCertChain = try tsc_await { self.rsaSelfSignedTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(_RSA.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            return XCTFail("Expected SigningEntity.unrecognized but got \(signingEntity)")
        }
        XCTAssertEqual("Test (RSA)", name)
        XCTAssertEqual("Test (RSA) org unit", organizationalUnit)
        XCTAssertEqual("Test (RSA) org", organization)
    }

    func testCMSBadSignature() async throws {
        let content = Array("per aspera ad astra".utf8)
        let signature = Array("bad signature".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)
        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: .init(),
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .invalid = status else {
            return XCTFail("Expected signature status to be .invalid but got \(status)")
        }
    }

    func testCMSInvalidSignature() async throws {
        let keyAndCertChain = try tsc_await { self.ecTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let signatureContent = Array("per aspera ad astra".utf8)
        let otherContent = Array("ad infinitum".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)
        let signature = try cmsProvider.sign(
            content: signatureContent,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: otherContent,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .invalid = status else {
            return XCTFail("Expected signature status to be .invalid but got \(status)")
        }
    }

    func testCMSUntrustedCertificate() async throws {
        let keyAndCertChain = try tsc_await { self.ecTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [], // trust store is empty
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .certificateNotTrusted = status else {
            return XCTFail("Expected signature status to be .certificateNotTrusted but got \(status)")
        }
    }

    func testCMSCheckCertificateValidityPeriod() async throws {
        let keyAndCertChain = try tsc_await { self.ecTestKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(P256.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        do {
            let verifierConfiguration = VerifierConfiguration(
                trustedRoots: [keyAndCertChain.rootCertificate],
                includeDefaultTrustStore: false,
                certificateExpiration: .enabled(
                    validationTime: signingIdentity.certificate.notValidBefore - .days(3)
                ),
                certificateRevocation: .disabled
            )

            let status = try await cmsProvider.status(
                signature: signature,
                content: content,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: ObservabilitySystem.NOOP
            )

            guard case .certificateInvalid(let reason) = status else {
                return XCTFail("Expected signature status to be .certificateInvalid but got \(status)")
            }
            XCTAssertTrue(reason.contains("not yet valid"))
        }

        do {
            let verifierConfiguration = VerifierConfiguration(
                trustedRoots: [keyAndCertChain.rootCertificate],
                includeDefaultTrustStore: false,
                certificateExpiration: .enabled(
                    validationTime: signingIdentity.certificate.notValidAfter + .days(3)
                ),
                certificateRevocation: .disabled
            )

            let status = try await cmsProvider.status(
                signature: signature,
                content: content,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: ObservabilitySystem.NOOP
            )

            guard case .certificateInvalid(let reason) = status else {
                return XCTFail("Expected signature status to be .certificateInvalid but got \(status)")
            }
            XCTAssertTrue(reason.contains("has expired"))
        }
    }

    func testCMSCheckCertificateRevocationStatus() async throws {
        // FIXME: skipping test temporarily until we figure out what causes Linux build failures https://github.com/apple/swift/pull/64285
        try XCTSkipIf(true)

        let ocspHandler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.post, URL(OCSPTestHelper.responderURI)):
                guard let requestBody = request.body else {
                    throw StringError("Empty request body")
                }
                let ocspRequest = try OCSPRequest(derEncoded: Array(requestBody))
                let nonce = try XCTUnwrap(ocspRequest.tbsRequest.requestExtensions?.ocspNonce)
                let singleRequest = try XCTUnwrap(ocspRequest.tbsRequest.requestList.first)
                let ocspResponse = OCSPResponse.successful(.signed(responses: [OCSPSingleResponse(
                    certID: singleRequest.certID,
                    certStatus: .unknown,
                    thisUpdate: try .init(Date() - .days(1)),
                    nextUpdate: try .init(Date() + .days(1))
                )], responseExtensions: { nonce }))
                return HTTPClientResponse(statusCode: 200, body: Data(ocspResponse.derEncodedBytes))
            default:
                throw StringError("method and url should match")
            }
        }

        let signingIdentity = SwiftSigningIdentity(
            certificate: OCSPTestHelper.chainWithSingleCertWithOCSP[0],
            privateKey: Certificate.PrivateKey(OCSPTestHelper.privateKey)
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(
            signatureAlgorithm: .ecdsaP256,
            customHTTPClient: HTTPClient(implementation: ocspHandler)
        )
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: [],
            observabilityScope: ObservabilitySystem.NOOP
        )

        // certificateRevocation = .strict doesn't allow status 'unknown'
        do {
            let verifierConfiguration = VerifierConfiguration(
                trustedRoots: [OCSPTestHelper.chainWithSingleCertWithOCSP[1].derEncodedBytes],
                includeDefaultTrustStore: false,
                certificateExpiration: .disabled,
                certificateRevocation: .strict(
                    validationTime: signingIdentity.certificate.notValidAfter - .days(3)
                )
            )

            let status = try await cmsProvider.status(
                signature: signature,
                content: content,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: ObservabilitySystem.NOOP
            )
            guard case .certificateInvalid(let reason) = status else {
                return XCTFail("Expected signature status to be .certificateInvalid but got \(status)")
            }
            XCTAssertTrue(reason.contains("status unknown"))
        }

        // certificateRevocation = .allowSoftFail allows status 'unknown'
        do {
            let verifierConfiguration = VerifierConfiguration(
                trustedRoots: [OCSPTestHelper.chainWithSingleCertWithOCSP[1].derEncodedBytes],
                includeDefaultTrustStore: false,
                certificateExpiration: .disabled,
                certificateRevocation: .allowSoftFail(
                    validationTime: signingIdentity.certificate.notValidAfter - .days(3)
                )
            )

            let status = try await cmsProvider.status(
                signature: signature,
                content: content,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: ObservabilitySystem.NOOP
            )
            guard case .valid = status else {
                return XCTFail("Expected signature status to be .valid but got \(status)")
            }
        }
    }

    func testCMSEndToEndWithRSAKeyADPCertificate() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif

        let keyAndCertChain = try tsc_await { rsaADPKeyAndCertChain(callback: $0) }
        let signingIdentity = SwiftSigningIdentity(
            certificate: try Certificate(keyAndCertChain.leafCertificate),
            privateKey: try Certificate
                .PrivateKey(_RSA.Signing.PrivateKey(derRepresentation: keyAndCertChain.privateKey))
        )
        let content = Array("per aspera ad astra".utf8)

        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: keyAndCertChain.intermediateCertificates,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [keyAndCertChain.rootCertificate],
            includeDefaultTrustStore: true,
            certificateExpiration: .enabled(validationTime: nil),
            certificateRevocation: .strict(validationTime: nil)
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }

        func rsaADPKeyAndCertChain(callback: (Result<KeyAndCertChain, Error>) -> Void) {
            do {
                try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                    let privateKey = try readFileContents(
                        in: fixturePath,
                        pathComponents: "Certificates", "development_key.p8"
                    )
                    let certificate = try readFileContents(
                        in: fixturePath,
                        pathComponents: "Certificates", "development.cer"
                    )

                    callback(.success(KeyAndCertChain(
                        privateKey: privateKey,
                        certificateChain: [certificate]
                    )))
                }
            } catch {
                callback(.failure(error))
            }
        }
    }

    #if os(macOS)
    func testCMS1_0_0EndToEndWithADPSigningIdentityFromKeychain() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_EC_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_EC_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let signingIdentity = matches[0]
        let content = Array("per aspera ad astra".utf8)

        let signatureFormat = SignatureFormat.cms_1_0_0
        // This call will trigger OS prompt(s) for key access
        let signature = try SignatureProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: [], // No need to pass intermediates for WWDR certs
            format: signatureFormat,
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [],
            includeDefaultTrustStore: true, // WWDR roots are in the default trust store
            certificateExpiration: .enabled(validationTime: nil),
            certificateRevocation: .strict(validationTime: nil)
        )

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
        switch signingEntity {
        case .recognized(_, let name, let organizationalUnit, let organization):
            XCTAssertNotNil(name)
            XCTAssertNotNil(organizationalUnit)
            XCTAssertNotNil(organization)
        case .unrecognized(let name, let organizationalUnit, let organization):
            XCTAssertNotNil(name)
            XCTAssertNotNil(organizationalUnit)
            XCTAssertNotNil(organization)
        }
    }
    #endif

    #if os(macOS)
    func testCMSEndToEndWithECKeyADPSigningIdentityFromKeychain() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_EC_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_EC_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let signingIdentity = matches[0]
        let content = Array("per aspera ad astra".utf8)
        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)

        // This call will trigger OS prompt(s) for key access
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: [], // No need to pass intermediates for WWDR certs
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [],
            includeDefaultTrustStore: true, // WWDR roots are in the default trust store
            certificateExpiration: .enabled(validationTime: nil),
            certificateRevocation: .strict(validationTime: nil)
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        switch signingEntity {
        case .recognized(_, let name, let organizationalUnit, let organization):
            XCTAssertNotNil(name)
            XCTAssertNotNil(organizationalUnit)
            XCTAssertNotNil(organization)
        case .unrecognized(let name, let organizationalUnit, let organization):
            XCTAssertNotNil(name)
            XCTAssertNotNil(organizationalUnit)
            XCTAssertNotNil(organization)
        }
    }
    #endif

    #if os(macOS)
    func testCMSEndToEndWithRSAKeyADPSigningIdentityFromKeychain() async throws {
        #if ENABLE_REAL_SIGNING_IDENTITY_TEST
        #else
        try XCTSkipIf(true)
        #endif

        guard let label = ProcessInfo.processInfo.environment["REAL_SIGNING_IDENTITY_RSA_LABEL"] else {
            throw XCTSkip("Skipping because 'REAL_SIGNING_IDENTITY_RSA_LABEL' env var is not set")
        }
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = identityStore.find(by: label)
        XCTAssertTrue(!matches.isEmpty)

        let signingIdentity = matches[0]
        let content = Array("per aspera ad astra".utf8)
        let cmsProvider = CMSSignatureProvider(signatureAlgorithm: .rsa)

        // This call will trigger OS prompt(s) for key access
        let signature = try cmsProvider.sign(
            content: content,
            identity: signingIdentity,
            intermediateCertificates: [], // No need to pass intermediates for WWDR certs
            observabilityScope: ObservabilitySystem.NOOP
        )

        let verifierConfiguration = VerifierConfiguration(
            trustedRoots: [],
            includeDefaultTrustStore: true, // WWDR roots are in the default trust store
            certificateExpiration: .enabled(validationTime: nil),
            certificateRevocation: .strict(validationTime: nil)
        )

        let status = try await cmsProvider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: ObservabilitySystem.NOOP
        )

        guard case .valid(let signingEntity) = status else {
            return XCTFail("Expected signature status to be .valid but got \(status)")
        }
        switch signingEntity {
        case .recognized(_, let name, let organizationalUnit, let organization):
            XCTAssertNotNil(name)
            XCTAssertNotNil(organizationalUnit)
            XCTAssertNotNil(organization)
        case .unrecognized(let name, let organizationalUnit, let organization):
            XCTAssertNotNil(name)
            XCTAssertNotNil(organizationalUnit)
            XCTAssertNotNil(organization)
        }
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

    private func ecSelfSignedTestKeyAndCertChain(callback: (Result<KeyAndCertChain, Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let privateKey = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_ec_self_signed_key.p8"
                )
                let certificate = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_ec_self_signed.cer"
                )

                callback(.success(KeyAndCertChain(
                    privateKey: privateKey,
                    certificateChain: [certificate]
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

    private func rsaSelfSignedTestKeyAndCertChain(callback: (Result<KeyAndCertChain, Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let privateKey = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_rsa_self_signed_key.p8"
                )
                let certificate = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "Test_rsa_self_signed.cer"
                )

                callback(.success(KeyAndCertChain(
                    privateKey: privateKey,
                    certificateChain: [certificate]
                )))
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

// MARK: - Helpers for OCSP related testing

enum OCSPTestHelper {
    static let responderURI = "http://ocsp.localhost"
    static let responderID = ResponderID.byName(try! DistinguishedName {
        CommonName("SwiftPM Test OCSP Responder")
    })

    static let privateKey = P256.Signing.PrivateKey()

    static func certificate(
        subject: DistinguishedName,
        issuer: DistinguishedName,
        ocspServer: String? = nil
    ) -> Certificate {
        try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(self.privateKey.publicKey),
            notValidBefore: Date() - .days(365),
            notValidAfter: Date() + .days(365),
            issuer: issuer,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: .init {
                if let ocspServer {
                    AuthorityInformationAccess([
                        AuthorityInformationAccess.AccessDescription(
                            method: .ocspServer,
                            location: GeneralName.uniformResourceIdentifier(ocspServer)
                        ),
                    ])
                }
            },
            issuerPrivateKey: .init(self.privateKey)
        )
    }

    static let ca1Name = try! DistinguishedName {
        CountryName("US")
        OrganizationName("SwiftPM Test")
        CommonName("SwiftPM Test CA 1")
    }

    static let intermediate1Name = try! DistinguishedName {
        CountryName("US")
        OrganizationName("SwiftPM Test")
        CommonName("SwiftPM Test Intermediate CA 1")
    }

    static let localhostLeafName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("SwiftPM Test")
        CommonName("localhost")
    }

    static let chainWithSingleCertWithOCSP = [
        certificate(subject: localhostLeafName, issuer: intermediate1Name, ocspServer: responderURI),
        certificate(subject: intermediate1Name, issuer: intermediate1Name),
    ]
}

extension Certificate {
    fileprivate var derEncodedBytes: [UInt8] {
        var serializer = DER.Serializer()
        try! serializer.serialize(self)
        return serializer.serializedBytes
    }
}

extension TimeInterval {
    private static let oneDay: TimeInterval = 60 * 60 * 24

    static func days(_ days: Int) -> TimeInterval {
        Double(days) * self.oneDay
    }
}

private let gregorianCalendar = Calendar(identifier: .gregorian)
private let utcTimeZone = TimeZone(identifier: "UTC")!

extension GeneralizedTime {
    init(_ date: Date) throws {
        let components = gregorianCalendar.dateComponents(in: utcTimeZone, from: date)
        try self.init(
            year: components.year!,
            month: components.month!,
            day: components.day!,
            hours: components.hour!,
            minutes: components.minute!,
            seconds: components.second!,
            fractionalSeconds: 0.0
        )
    }
}

extension BasicOCSPResponse {
    static func signed(responseData: OCSPResponseData) -> Self {
        // TODO: actually sign the response once we validate the signature
        .init(
            responseData: responseData,
            signatureAlgorithm: .ecdsaWithSHA256,
            signature: .init(bytes: [][...])
        )
    }

    static func signed(
        version: OCSPVersion = .v1,
        responderID: ResponderID = OCSPTestHelper.responderID,
        producedAt: GeneralizedTime = try! .init(Date()),
        responses: [OCSPSingleResponse],
        @ExtensionsBuilder responseExtensions: () -> Certificate.Extensions = { .init() }
    ) -> Self {
        .signed(responseData: .init(
            version: version,
            responderID: responderID,
            producedAt: producedAt,
            responses: responses,
            responseExtensions: responseExtensions()
        ))
    }
}

extension OCSPResponse {
    fileprivate var derEncodedBytes: [UInt8] {
        var serializer = DER.Serializer()
        try! serializer.serialize(self)
        return serializer.serializedBytes
    }
}
