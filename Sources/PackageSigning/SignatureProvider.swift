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

import struct Foundation.Data
import struct Foundation.Date

#if USE_IMPL_ONLY_IMPORTS
#if canImport(Security)
@_implementationOnly import Security
#endif

@_implementationOnly import SwiftASN1
@_implementationOnly @_spi(CMS) import X509
#else
#if canImport(Security)
import Security
#endif

import SwiftASN1
@_spi(CMS) import X509
#endif

import Basics

// MARK: - Public signature API

public enum SignatureProvider {
    public static func sign(
        content: [UInt8],
        identity: SigningIdentity,
        intermediateCertificates: [[UInt8]],
        format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) throws -> [UInt8] {
        let provider = format.provider
        return try provider.sign(
            content: content,
            identity: identity,
            intermediateCertificates: intermediateCertificates,
            observabilityScope: observabilityScope
        )
    }

    public static func status(
        signature: [UInt8],
        content: [UInt8],
        format: SignatureFormat,
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus {
        let provider = format.provider
        return try await provider.status(
            signature: signature,
            content: content,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: observabilityScope
        )
    }

    public static func extractSigningEntity(
        signature: [UInt8],
        format: SignatureFormat,
        verifierConfiguration: VerifierConfiguration
    ) async throws -> SigningEntity {
        let provider = format.provider
        return try await provider.extractSigningEntity(
            signature: signature,
            format: format,
            verifierConfiguration: verifierConfiguration
        )
    }
}

public struct VerifierConfiguration {
    public var trustedRoots: [[UInt8]]
    public var includeDefaultTrustStore: Bool
    public var certificateExpiration: CertificateExpiration
    public var certificateRevocation: CertificateRevocation

    // for testing
    init(
        trustedRoots: [[UInt8]],
        includeDefaultTrustStore: Bool,
        certificateExpiration: CertificateExpiration,
        certificateRevocation: CertificateRevocation
    ) {
        self.trustedRoots = trustedRoots
        self.includeDefaultTrustStore = includeDefaultTrustStore
        self.certificateExpiration = certificateExpiration
        self.certificateRevocation = certificateRevocation
    }

    public init() {
        self.trustedRoots = []
        self.includeDefaultTrustStore = true
        self.certificateExpiration = .disabled
        self.certificateRevocation = .disabled
    }

    public enum CertificateExpiration {
        case enabled(validationTime: Date?)
        case disabled
    }

    public enum CertificateRevocation {
        case strict(validationTime: Date?)
        case allowSoftFail(validationTime: Date?)
        case disabled
    }
}

public enum SignatureStatus: Equatable {
    case valid(SigningEntity)
    case invalid(String)
    case certificateInvalid(String)
    case certificateNotTrusted(SigningEntity)
}

public enum SigningError: Error {
    case signingFailed(String)
    case keyDoesNotSupportSignatureAlgorithm
    case signingIdentityNotSupported
    case unableToValidateSignature(String)
    case invalidSignature(String)
    case certificateInvalid(String)
    case certificateNotTrusted(SigningEntity)
}

// MARK: - Signature formats and providers

public enum SignatureFormat: String {
    case cms_1_0_0 = "cms-1.0.0"

    public var signingKeyType: SigningKeyType {
        switch self {
        case .cms_1_0_0:
            return .p256
        }
    }

    var provider: SignatureProviderProtocol {
        switch self {
        case .cms_1_0_0:
            return CMSSignatureProvider(signatureAlgorithm: .ecdsaP256)
        }
    }
}

public enum SigningKeyType {
    case p256
    // RSA support is internal/testing only, thus not included
}

enum SignatureAlgorithm {
    case ecdsaP256
    case rsa

    var certificateSignatureAlgorithm: Certificate.SignatureAlgorithm {
        switch self {
        case .ecdsaP256:
            return .ecdsaWithSHA256
        case .rsa:
            return .sha256WithRSAEncryption
        }
    }
}

protocol SignatureProviderProtocol {
    func sign(
        content: [UInt8],
        identity: SigningIdentity,
        intermediateCertificates: [[UInt8]],
        observabilityScope: ObservabilityScope
    ) throws -> [UInt8]

    func status(
        signature: [UInt8],
        content: [UInt8],
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus

    func extractSigningEntity(
        signature: [UInt8],
        format: SignatureFormat,
        verifierConfiguration: VerifierConfiguration
    ) async throws -> SigningEntity
}

// MARK: - CMS signature provider

struct CMSSignatureProvider: SignatureProviderProtocol {
    let signatureAlgorithm: SignatureAlgorithm
    let httpClient: HTTPClient

    init(
        signatureAlgorithm: SignatureAlgorithm,
        customHTTPClient: HTTPClient? = .none
    ) {
        self.signatureAlgorithm = signatureAlgorithm
        self.httpClient = customHTTPClient ?? HTTPClient()
    }

    func sign(
        content: [UInt8],
        identity: SigningIdentity,
        intermediateCertificates: [[UInt8]],
        observabilityScope: ObservabilityScope
    ) throws -> [UInt8] {
        #if canImport(Security)
        if CFGetTypeID(identity as CFTypeRef) == SecIdentityGetTypeID() {
            let secIdentity = identity as! SecIdentity // !-safe because we ensure type above

            var privateKey: SecKey?
            let keyStatus = SecIdentityCopyPrivateKey(secIdentity, &privateKey)
            guard keyStatus == errSecSuccess, let privateKey else {
                throw SigningError.signingFailed("unable to get private key from SecIdentity: status \(keyStatus)")
            }

            let signature = try privateKey.sign(content: content, algorithm: self.signatureAlgorithm)

            do {
                let intermediateCertificates = try intermediateCertificates.map { try Certificate($0) }

                return try CMS.sign(
                    signatureBytes: ASN1OctetString(contentBytes: ArraySlice(signature)),
                    signatureAlgorithm: self.signatureAlgorithm.certificateSignatureAlgorithm,
                    additionalIntermediateCertificates: intermediateCertificates,
                    certificate: try Certificate(secIdentity: secIdentity)
                )
            } catch {
                throw SigningError.signingFailed("\(error.interpolationDescription)")
            }
        }
        #endif

        guard let swiftSigningIdentity = identity as? SwiftSigningIdentity else {
            throw SigningError.signingIdentityNotSupported
        }

        do {
            let intermediateCertificates = try intermediateCertificates.map { try Certificate($0) }

            return try CMS.sign(
                content,
                signatureAlgorithm: self.signatureAlgorithm.certificateSignatureAlgorithm,
                additionalIntermediateCertificates: intermediateCertificates,
                certificate: swiftSigningIdentity.certificate,
                privateKey: swiftSigningIdentity.privateKey
            )
        } catch let error as CertificateError where error.code == .unsupportedSignatureAlgorithm {
            throw SigningError.keyDoesNotSupportSignatureAlgorithm
        } catch {
            throw SigningError.signingFailed("\(error.interpolationDescription)")
        }
    }

    func status(
        signature: [UInt8],
        content: [UInt8],
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus {
        do {
            var trustRoots: [Certificate] = []
            if verifierConfiguration.includeDefaultTrustStore {
                trustRoots.append(contentsOf: CertificateStores.defaultTrustRoots)
            }
            trustRoots.append(contentsOf: try verifierConfiguration.trustedRoots.map { try Certificate($0) })

            let result = await CMS.isValidSignature(
                dataBytes: content,
                signatureBytes: signature,
                // The intermediates supplied here will be combined with those
                // included in the signature to build cert chain for validation.
                //
                // Those who use ADP certs for signing are not required to provide
                // the entire cert chain, thus we must supply WWDR intermediates
                // here so that the chain can be constructed during validation.
                // Whether the signing cert is trusted still depends on whether
                // the WWDR roots are in the trust store or not, which by default
                // they are but user may disable that through configuration.
                additionalIntermediateCertificates: Certificates.wwdrIntermediates,
                trustRoots: CertificateStore(trustRoots)
            ) {
                self.buildPolicySet(configuration: verifierConfiguration, httpClient: self.httpClient)
            }
            

            switch result {
            case .success(let valid):
                let signingEntity = SigningEntity.from(certificate: valid.signer)
                return .valid(signingEntity)
            case .failure(CMS.VerificationError.unableToValidateSigner(let failure)):
                if failure.validationFailures.isEmpty {
                    let signingEntity = SigningEntity.from(certificate: failure.signer)
                    return .certificateNotTrusted(signingEntity)
                } else {
                    observabilityScope
                        .emit(
                            info: "cannot validate certificate chain. Validation failures: \(failure.validationFailures)"
                        )
                    return .certificateInvalid("failures: \(failure.validationFailures.map(\.policyFailureReason))")
                }
            case .failure(CMS.VerificationError.invalidCMSBlock(let error)):
                return .invalid(error.reason)
            case .failure(let error):
                return .invalid("\(error.interpolationDescription)")
            }
        } catch {
            throw SigningError.unableToValidateSignature("\(error.interpolationDescription)")
        }
    }

    func extractSigningEntity(
        signature: [UInt8],
        format: SignatureFormat,
        verifierConfiguration: VerifierConfiguration
    ) async throws -> SigningEntity {
        switch format {
        case .cms_1_0_0:
            do {
                let cmsSignature = try CMSSignature(derEncoded: signature)
                let signers = try cmsSignature.signers
                guard signers.count == 1, let signer = signers.first else {
                    throw SigningError.invalidSignature("expected 1 signer but got \(signers.count)")
                }

                let signingCertificate = signer.certificate

                var trustRoots: [Certificate] = []
                if verifierConfiguration.includeDefaultTrustStore {
                    trustRoots.append(contentsOf: CertificateStores.defaultTrustRoots)
                }
                trustRoots.append(contentsOf: try verifierConfiguration.trustedRoots.map { try Certificate($0) })

                // Verifier uses these to build cert chain for validation
                // (see also notes in `status` method)
                var untrustedIntermediates: [Certificate] = []
                // WWDR intermediates are not required when signing with ADP certs,
                // (i.e., these intermediates may not be in the signature), hence
                // we include them here to ensure Verifier can build cert chain.
                untrustedIntermediates.append(contentsOf: Certificates.wwdrIntermediates)
                // For self-signed certificate, the signature should include intermediate(s).
                untrustedIntermediates.append(contentsOf: cmsSignature.certificates)

                var verifier = Verifier(rootCertificates: CertificateStore(trustRoots)) {
                    self.buildPolicySet(configuration: verifierConfiguration, httpClient: self.httpClient)
                }
                let result = await verifier.validate(
                    leafCertificate: signingCertificate,
                    intermediates: CertificateStore(untrustedIntermediates)
                )

                switch result {
                case .validCertificate:
                    return SigningEntity.from(certificate: signingCertificate)
                case .couldNotValidate(let validationFailures):
                    if validationFailures.isEmpty {
                        let signingEntity = SigningEntity.from(certificate: signingCertificate)
                        throw SigningError.certificateNotTrusted(signingEntity)
                    } else {
                        throw SigningError
                            .certificateInvalid("failures: \(validationFailures.map(\.policyFailureReason))")
                    }
                }
            } catch let error as SigningError {
                throw error
            } catch {
                throw SigningError.invalidSignature("\(error.interpolationDescription)")
            }
        }
    }
}

#if canImport(Security)
extension SecKey {
    func sign(content: [UInt8], algorithm: SignatureAlgorithm) throws -> [UInt8] {
        let secKeyAlgorithm: SecKeyAlgorithm
        switch algorithm {
        case .ecdsaP256:
            secKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        case .rsa:
            secKeyAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        }

        guard SecKeyIsAlgorithmSupported(self, .sign, secKeyAlgorithm) else {
            throw SigningError.keyDoesNotSupportSignatureAlgorithm
        }

        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            self,
            secKeyAlgorithm,
            Data(content) as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() as Error? {
                throw SigningError.signingFailed("\(error.interpolationDescription)")
            }
            throw SigningError.signingFailed("Failed to sign with SecKey")
        }
        return Array(signatureData)
    }
}
#endif
