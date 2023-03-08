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

#if canImport(Security)
@_implementationOnly import Security
#endif

import Basics
@_implementationOnly import SwiftASN1
@_implementationOnly @_spi(CMS) import X509

public enum SignatureProvider {
    public static func sign(
        content: [UInt8],
        identity: SigningIdentity,
        intermediateCertificates: [[UInt8]],
        format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> [UInt8] {
        let provider = format.provider
        return try await provider.sign(
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
}

public struct VerifierConfiguration {
    public var trustedRoots: [[UInt8]]
    public var certificateExpiration: CertificateExpiration
    public var certificateRevocation: CertificateRevocation

    public init() {
        self.trustedRoots = []
        self.certificateExpiration = .disabled
        self.certificateRevocation = .disabled
    }

    public enum CertificateExpiration {
        case enabled
        case disabled
    }

    public enum CertificateRevocation {
        case strict
        case allowSoftFail
        case disabled
    }
}

public enum SignatureStatus: Equatable {
    case valid(SigningEntity)
    case invalid(String)
    case certificateInvalid(String)
    case certificateNotTrusted(SigningEntity)
}

public enum CertificateRevocationStatus {
    case valid
    case revoked
    case unknown
}

public enum SigningError: Error {
    case signingFailed(String)
    case keyDoesNotSupportSignatureAlgorithm
    case signingIdentityNotSupported
}

// MARK: - Signature formats and their provider

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
    ) async throws -> [UInt8]

    func status(
        signature: [UInt8],
        content: [UInt8],
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus
}

// MARK: - CMS signature provider

struct CMSSignatureProvider: SignatureProviderProtocol {
    let signatureAlgorithm: SignatureAlgorithm

    init(signatureAlgorithm: SignatureAlgorithm) {
        self.signatureAlgorithm = signatureAlgorithm
    }

    func sign(
        content: [UInt8],
        identity: SigningIdentity,
        intermediateCertificates: [[UInt8]],
        observabilityScope: ObservabilityScope
    ) async throws -> [UInt8] {
        #if canImport(Security)
        if CFGetTypeID(identity as CFTypeRef) == SecIdentityGetTypeID() {
            let secIdentity = identity as! SecIdentity // !-safe because we ensure type above

            var privateKey: SecKey?
            let keyStatus = SecIdentityCopyPrivateKey(secIdentity, &privateKey)
            guard keyStatus == errSecSuccess, let privateKey = privateKey else {
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
                throw SigningError.signingFailed("\(error)")
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
            throw SigningError.signingFailed("\(error)")
        }
    }

    func status(
        signature: [UInt8],
        content: [UInt8],
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus {
        let result = await CMS.isValidSignature(
            dataBytes: content,
            signatureBytes: signature,
            // TODO: pass default intermediates
            additionalIntermediateCertificates: [],
            trustRoots: CertificateStore(
                try verifierConfiguration.trustedRoots.map { try Certificate($0) }
            ),
            // TODO: build policies based on config
            policy: PolicySet(policies: [])
        )

        switch result {
        case .success(let valid):
            let signingEntity = SigningEntity(certificate: valid.signer)
            return .valid(signingEntity)
        case .failure(CMS.VerificationError.unableToValidateSigner(let failure)):
            if failure.validationFailures.isEmpty {
                let signingEntity = SigningEntity(certificate: failure.signer)
                return .certificateNotTrusted(signingEntity)
            } else {
                return .certificateInvalid("\(failure.validationFailures)") // TODO: format error message
            }
        case .failure(CMS.VerificationError.invalidCMSBlock(let error)):
            return .invalid(error.reason)
        case .failure(let error):
            return .invalid("\(error)")
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
                throw SigningError.signingFailed("\(error)")
            }
            throw SigningError.signingFailed("Failed to sign with SecKey")
        }
        return Array(signatureData)
    }
}
#endif
