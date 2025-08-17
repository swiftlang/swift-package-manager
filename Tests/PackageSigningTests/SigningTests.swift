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

import _CryptoExtras // for RSA
import Basics
import Crypto
import Foundation
@testable import PackageSigning
import _InternalTestSupport
import SwiftASN1
@testable import X509 // need internal APIs for OCSP testing
import Testing

struct SigningTests {
    @Test
    func CMS1_0_0EndToEnd() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (EC) leaf" == name)
        #expect("Test (EC) org unit" == organizationalUnit)
        #expect("Test (EC) org" == organization)
    }

    @Test
    func CMSEndToEndWithECSigningIdentity() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (EC) leaf" == name)
        #expect("Test (EC) org unit" == organizationalUnit)
        #expect("Test (EC) org" == organization)
    }

    @Test
    func CMSEndToEndWithRSASigningIdentity() async throws {
        let keyAndCertChain = try self.rsaTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (RSA) leaf" == name)
        #expect("Test (RSA) org unit" == organizationalUnit)
        #expect("Test (RSA) org" == organization)
    }

    @Test
    func CMSWrongKeyTypeForSignatureAlgorithm() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
            Issue.record("Expected error")
        } catch {
            guard case SigningError.keyDoesNotSupportSignatureAlgorithm = error else {
                Issue.record(
                    "Expected SigningError.keyDoesNotSupportSignatureAlgorithm but got \(error)")
                return
            }
        }
    }

    @Test
    func CMS1_0_0EndToEndWithSelfSignedCertificate() async throws {
        let keyAndCertChain = try self.ecSelfSignedTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (EC)" == name)
        #expect("Test (EC) org unit" == organizationalUnit)
        #expect("Test (EC) org" == organization)
    }

    @Test
    func CMSEndToEndWithSelfSignedECSigningIdentity() async throws {
        let keyAndCertChain = try self.ecSelfSignedTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (EC)" == name)
        #expect("Test (EC) org unit" == organizationalUnit)
        #expect("Test (EC) org" == organization)
    }

    @Test
    func CMSEndToEndWithSelfSignedRSASigningIdentity() async throws {
        let keyAndCertChain = try self.rsaSelfSignedTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (RSA)" == name)
        #expect("Test (RSA) org unit" == organizationalUnit)
        #expect("Test (RSA) org" == organization)
    }

    @Test
    func CMSBadSignature() async throws {
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
            Issue.record("Expected signature status to be .invalid but got \(status)")
            return
        }
    }

    @Test
    func CMSInvalidSignature() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
            Issue.record("Expected signature status to be .invalid but got \(status)")
            return
        }
    }

    @Test
    func CMSUntrustedCertificate() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
            Issue.record(
                "Expected signature status to be .certificateNotTrusted but got \(status)")
            return
        }
    }

    @Test
    func CMSCheckCertificateValidityPeriod() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
                Issue.record(
                    "Expected signature status to be .certificateInvalid but got \(status)")
                return
            }
            #expect(reason.contains("not yet valid"))
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
                Issue.record(
                    "Expected signature status to be .certificateInvalid but got \(status)")
                return
            }
            #expect(reason.contains("has expired"))
        }
    }

    @Test
    func CMSCheckCertificateRevocationStatus() async throws {
        let leafName = try OCSPTestHelper.distinguishedName(commonName: "localhost")
        let intermediateName = try OCSPTestHelper.distinguishedName(commonName: "SwiftPM Test Intermediate CA")
        let caName = try OCSPTestHelper.distinguishedName(commonName: "SwiftPM Test CA")

        let leafPrivateKey = P256.Signing.PrivateKey()
        let intermediatePrivateKey = P256.Signing.PrivateKey()
        let caPrivateKey = P256.Signing.PrivateKey()

        let ocspResponderURI = "http://ocsp.local"
        let chainWithSingleCertWithOCSP = [
            try OCSPTestHelper.certificate(
                subject: leafName,
                publicKey: leafPrivateKey.publicKey,
                issuer: intermediateName,
                issuerPrivateKey: intermediatePrivateKey,
                isIntermediate: false,
                isCodeSigning: true,
                ocspServer: ocspResponderURI
            ),
            try OCSPTestHelper.certificate(
                subject: intermediateName,
                publicKey: intermediatePrivateKey.publicKey,
                issuer: caName,
                issuerPrivateKey: caPrivateKey,
                isIntermediate: true,
                isCodeSigning: false
            ),
        ]

        let signingIdentity = SwiftSigningIdentity(
            certificate: chainWithSingleCertWithOCSP[0],
            privateKey: Certificate.PrivateKey(leafPrivateKey)
        )

        let validationTime = signingIdentity.certificate.notValidAfter - .days(3)

        let ocspHandler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.post, URL(ocspResponderURI)):
                guard let requestBody = request.body else {
                    throw StringError("Empty request body")
                }

                let ocspRequest = try OCSPRequest(derEncoded: Array(requestBody))

                guard let nonce = try? ocspRequest.tbsRequest.requestExtensions?.ocspNonce else {
                    throw StringError("Missing nonce")
                }
                guard let singleRequest = ocspRequest.tbsRequest.requestList.first else {
                    throw StringError("Missing OCSP request")
                }

                let ocspResponse = try OCSPResponse.successful(
                    .signed(
                        responderID: ResponderID.byName(intermediateName),
                        producedAt: GeneralizedTime(validationTime),
                        responses: [
                            OCSPSingleResponse(
                                certID: singleRequest.certID,
                                certStatus: .unknown,
                                thisUpdate: GeneralizedTime(validationTime - .days(1)),
                                nextUpdate: GeneralizedTime(validationTime + .days(1))
                            )
                        ],
                        privateKey: intermediatePrivateKey,
                        responseExtensions: { nonce }
                    ))
                return HTTPClientResponse(
                    statusCode: 200, body: try Data(ocspResponse.derEncodedBytes()))
            default:
                throw StringError("method and url should match")
            }
        }

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
                trustedRoots: [try chainWithSingleCertWithOCSP[1].derEncodedBytes()],
                includeDefaultTrustStore: false,
                certificateExpiration: .disabled,
                certificateRevocation: .strict(validationTime: validationTime)
            )

            let status = try await cmsProvider.status(
                signature: signature,
                content: content,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: ObservabilitySystem.NOOP
            )
            guard case .certificateInvalid(let reason) = status else {
                Issue.record(
                    "Expected signature status to be .certificateInvalid but got \(status)")
                return
            }
            #expect(reason.contains("status unknown"))
        }

        // certificateRevocation = .allowSoftFail allows status 'unknown'
        do {
            let verifierConfiguration = VerifierConfiguration(
                trustedRoots: [try chainWithSingleCertWithOCSP[1].derEncodedBytes()],
                includeDefaultTrustStore: false,
                certificateExpiration: .disabled,
                certificateRevocation: .allowSoftFail(validationTime: validationTime)
            )

            let status = try await cmsProvider.status(
                signature: signature,
                content: content,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: ObservabilitySystem.NOOP
            )
            guard case .valid = status else {
                Issue.record("Expected signature status to be .valid but got \(status)")
                return
            }
        }
    }

    @Test(
        .enabled(if: isRealSigningIdentitTestDefined)
    )
    func CMSEndToEndWithRSAKeyADPCertificate() async throws {
        let keyAndCertChain = try rsaADPKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }

        func rsaADPKeyAndCertChain() throws -> KeyAndCertChain {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let privateKey = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "development_key.p8"
                )
                let certificate = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "development.cer"
                )

                return KeyAndCertChain(
                    privateKey: privateKey,
                    certificateChain: [certificate]
                )
            }
        }
    }

    @Test(
        .enabled(if: isRealSigningIdentitTestDefined)
    )
    func CMSEndToEndWithECKeyADPCertificate() async throws {
        let keyAndCertChain = try ecADPKeyAndCertChain()
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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }

        func ecADPKeyAndCertChain() throws -> KeyAndCertChain {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let privateKey = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "swift_package_key.p8"
                )
                let certificate = try readFileContents(
                    in: fixturePath,
                    pathComponents: "Certificates", "swift_package.cer"
                )

                return KeyAndCertChain(
                    privateKey: privateKey,
                    certificateChain: [certificate]
                )
            }
        }
    }

    // #if os(macOS)
    @Test(
        .enabled(if: ProcessInfo.hostOperatingSystem == .windows),
        .enabled(if: isRealSigningIdentitTestDefined),
        .enabled(if: isRealSigningIdentyEcLabelEnvVarSet),
    )
    func CMS1_0_0EndToEndWithADPSigningIdentityFromKeychain() async throws {
        let label = try #require(Environment.current["REAL_SIGNING_IDENTITY_EC_LABEL"])

        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = identityStore.find(by: label)
        #expect(!matches.isEmpty)

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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        switch signingEntity {
        case .recognized:
            break
        case .unrecognized(let name, let organizationalUnit, let organization):
            #expect(name != nil)
            #expect(organizationalUnit != nil)
            #expect(organization != nil)
        }
    }
    // #endif

    // #if os(macOS)
    @Test(
        .enabled(if: ProcessInfo.hostOperatingSystem == .windows),
        .enabled(if: isRealSigningIdentitTestDefined),
        .enabled(if: isRealSigningIdentyEcLabelEnvVarSet),
    )
    func CMSEndToEndWithECKeyADPSigningIdentityFromKeychain() async throws {
        let label = try #require(Environment.current["REAL_SIGNING_IDENTITY_EC_LABEL"])
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = identityStore.find(by: label)
        #expect(!matches.isEmpty)

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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        switch signingEntity {
        case .recognized:
            break
        case .unrecognized(let name, let organizationalUnit, let organization):
            #expect(name != nil)
            #expect(organizationalUnit != nil)
            #expect(organization != nil)
        }
    }
    // #endif

    // #if os(macOS)
    @Test(
        .enabled(if: ProcessInfo.hostOperatingSystem == .windows),
        .enabled(if: isRealSigningIdentitTestDefined),
        .enabled(if: isRealSigningIdentyEcLabelEnvVarSet),
    )
    func testCMSEndToEndWithRSAKeyADPSigningIdentityFromKeychain() async throws {
        let label = try #require(Environment.current["REAL_SIGNING_IDENTITY_EC_LABEL"])
        let identityStore = SigningIdentityStore(observabilityScope: ObservabilitySystem.NOOP)
        let matches = identityStore.find(by: label)
        #expect(!matches.isEmpty)

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
            Issue.record("Expected signature status to be .valid but got \(status)")
            return
        }
        switch signingEntity {
        case .recognized:
            break
        case .unrecognized(let name, let organizationalUnit, let organization):
            #expect(name != nil)
            #expect(organizationalUnit != nil)
            #expect(organization != nil)
        }
    }
    // #endif

    @Test
    func CMS1_0_0ExtractSigningEntity() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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

        let signingEntity = try await SignatureProvider.extractSigningEntity(
            signature: signature,
            format: signatureFormat,
            verifierConfiguration: verifierConfiguration
        )

        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (EC) leaf" == name)
        #expect("Test (EC) org unit" == organizationalUnit)
        #expect("Test (EC) org" == organization)
    }

    @Test
    func CMS1_0_0ExtractSigningEntityWithSelfSignedCertificate() async throws {
        let keyAndCertChain = try self.ecSelfSignedTestKeyAndCertChain()
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

        let signingEntity = try await SignatureProvider.extractSigningEntity(
            signature: signature,
            format: signatureFormat,
            verifierConfiguration: verifierConfiguration
        )

        guard case .unrecognized(let name, let organizationalUnit, let organization) = signingEntity else {
            Issue.record("Expected SigningEntity.unrecognized but got \(signingEntity)")
            return
        }
        #expect("Test (EC)" == name)
        #expect("Test (EC) org unit" == organizationalUnit)
        #expect("Test (EC) org" == organization)
    }

    @Test
    func CMS1_0_0ExtractSigningEntityWithUntrustedCertificate() async throws {
        let keyAndCertChain = try self.ecTestKeyAndCertChain()
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
            trustedRoots: [], // trust store is empty
            includeDefaultTrustStore: false,
            certificateExpiration: .disabled,
            certificateRevocation: .disabled
        )

        do {
            _ = try await SignatureProvider.extractSigningEntity(
                signature: signature,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration
            )
            Issue.record("expected error")
        } catch {
            guard case SigningError.certificateNotTrusted = error else {
                Issue.record(
                    "Expected error to be SigningError.certificateNotTrusted but got \(error)")
                return
            }
        }
    }

    private func ecTestKeyAndCertChain() throws -> KeyAndCertChain {
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

            return KeyAndCertChain(
                privateKey: privateKey,
                certificateChain: [certificate, intermediateCA, rootCA]
            )
        }
    }

    private func ecSelfSignedTestKeyAndCertChain() throws -> KeyAndCertChain {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let privateKey = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates", "Test_ec_self_signed_key.p8"
            )
            let certificate = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates", "Test_ec_self_signed.cer"
            )

            return KeyAndCertChain(
                privateKey: privateKey,
                certificateChain: [certificate]
            )
        }
    }

    private func rsaTestKeyAndCertChain() throws -> KeyAndCertChain {
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

            return KeyAndCertChain(
                privateKey: privateKey,
                certificateChain: [certificate, intermediateCA, rootCA]
            )
        }
    }

    private func rsaSelfSignedTestKeyAndCertChain() throws -> KeyAndCertChain {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let privateKey = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates", "Test_rsa_self_signed_key.p8"
            )
            let certificate = try readFileContents(
                in: fixturePath,
                pathComponents: "Certificates", "Test_rsa_self_signed.cer"
            )

            return KeyAndCertChain(
                privateKey: privateKey,
                certificateChain: [certificate]
            )
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
    static func certificate(
        subject: DistinguishedName,
        publicKey: P256.Signing.PublicKey,
        issuer: DistinguishedName,
        issuerPrivateKey: P256.Signing.PrivateKey,
        isIntermediate: Bool,
        isCodeSigning: Bool,
        ocspServer: String? = nil
    ) throws -> Certificate {
        try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(publicKey),
            notValidBefore: Date() - .days(365),
            notValidAfter: Date() + .days(365),
            issuer: issuer,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: .init {
                if isIntermediate {
                    Critical(
                        BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                    )
                }
                if isCodeSigning {
                    Critical(
                        try ExtendedKeyUsage([ExtendedKeyUsage.Usage.codeSigning])
                    )
                }
                if let ocspServer {
                    AuthorityInformationAccess([
                        AuthorityInformationAccess.AccessDescription(
                            method: .ocspServer,
                            location: GeneralName.uniformResourceIdentifier(ocspServer)
                        ),
                    ])
                }
            },
            issuerPrivateKey: .init(issuerPrivateKey)
        )
    }

    static func distinguishedName(
        countryName: String = "US",
        organizationName: String = "SwiftPM Test",
        commonName: String
    ) throws -> DistinguishedName {
        try DistinguishedName {
            CountryName(countryName)
            OrganizationName(organizationName)
            CommonName(commonName)
        }
    }
}

extension Certificate {
    fileprivate func derEncodedBytes() throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(self)
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

extension BasicOCSPResponse {
    static func signed(
        responseData: OCSPResponseData,
        privateKey: P256.Signing.PrivateKey,
        certs: [Certificate]?
    ) throws -> Self {
        var serializer = DER.Serializer()
        try serializer.serialize(responseData)
        let tbsCertificateBytes = serializer.serializedBytes[...]

        let digest = SHA256.hash(data: tbsCertificateBytes)
        let signature = try privateKey.signature(for: digest)

        return try .init(
            responseData: responseData,
            signatureAlgorithm: .ecdsaWithSHA256,
            signature: .init(bytes: Array(signature.derRepresentation)[...]),
            certs: certs
        )
    }

    static func signed(
        version: OCSPVersion = .v1,
        responderID: ResponderID,
        producedAt: GeneralizedTime,
        responses: [OCSPSingleResponse],
        privateKey: P256.Signing.PrivateKey,
        certs: [Certificate]? = [],
        @ExtensionsBuilder responseExtensions: () throws -> Result<Certificate.Extensions, any Error> = {
            // workaround for rdar://108897294
            Result.success(Certificate.Extensions())
        }
    ) throws -> Self {
        try .signed(
            responseData: .init(
                version: version,
                responderID: responderID,
                producedAt: producedAt,
                responses: responses,
                responseExtensions: try .init(builder: responseExtensions)
            ),
            privateKey: privateKey,
            certs: certs
        )
    }

    init(
        responseData: OCSPResponseData,
        signatureAlgorithm: AlgorithmIdentifier,
        signature: ASN1BitString,
        certs: [Certificate]?
    ) throws {
        self.init(
            responseData: responseData,
            responseDataBytes: try DER.Serializer.serialized(element: responseData)[...],
            signatureAlgorithm: signatureAlgorithm,
            signature: signature,
            certs: certs
        )
    }
}

extension OCSPResponse {
    fileprivate func derEncodedBytes() throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(self)
        return serializer.serializedBytes
    }
}
