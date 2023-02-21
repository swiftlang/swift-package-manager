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

#if os(macOS)
import Security
#endif

import Basics

public struct SignatureProvider {
    public init() {}

    public func sign(
        _ content: Data,
        with identity: SigningIdentity,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Data {
        let provider = format.provider
        return try await provider.sign(content, with: identity, observabilityScope: observabilityScope)
    }

    public func status(
        of signature: Data,
        for content: Data,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus {
        let provider = format.provider
        return try await provider.status(of: signature, for: content, observabilityScope: observabilityScope)
    }
}

public enum SignatureStatus: Equatable {
    case valid
    case invalid(String)
    case certificateInvalid(String)
    case certificateNotTrusted
}

extension Certificate {
    public enum RevocationStatus {
        case valid
        case revoked
        case unknown
    }
}

public enum SigningError: Error {
    case encodeInitializationFailed(String)
    case decodeInitializationFailed(String)
    case signingFailed(String)
    case signatureInvalid(String)
}

protocol SignatureProviderProtocol {
    func sign(
        _ content: Data,
        with identity: SigningIdentity,
        observabilityScope: ObservabilityScope
    ) async throws -> Data

    func status(
        of signature: Data,
        for content: Data,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus

    func signingEntity(of signature: Data) throws -> SigningEntity
}

public enum SignatureFormat: String {
    case cms_1_0_0 = "cms-1.0.0"

    var provider: SignatureProviderProtocol {
        switch self {
        case .cms_1_0_0:
            return CMSSignatureProvider(format: self)
        }
    }
}

struct CMSSignatureProvider: SignatureProviderProtocol {
    let format: SignatureFormat

    init(format: SignatureFormat) {
        precondition(format.rawValue.hasPrefix("cms-"), "Unsupported signature format '\(format)'")
        self.format = format
    }

    func sign(
        _ content: Data,
        with identity: SigningIdentity,
        observabilityScope: ObservabilityScope
    ) async throws -> Data {
        try self.validate(identity: identity)

        #if os(macOS)
        if CFGetTypeID(identity as CFTypeRef) == SecIdentityGetTypeID() {
            var cmsEncoder: CMSEncoder?
            var status = CMSEncoderCreate(&cmsEncoder)
            guard status == errSecSuccess, let cmsEncoder = cmsEncoder else {
                throw SigningError.encodeInitializationFailed("Unable to create CMSEncoder. Error: \(status)")
            }

            CMSEncoderAddSigners(cmsEncoder, identity as! SecIdentity)
            CMSEncoderSetHasDetachedContent(cmsEncoder, true) // Detached signature
            CMSEncoderSetSignerAlgorithm(cmsEncoder, kCMSEncoderDigestAlgorithmSHA256)
            CMSEncoderAddSignedAttributes(cmsEncoder, CMSSignedAttributes.attrSigningTime)
            CMSEncoderSetCertificateChainMode(cmsEncoder, .signerOnly)

            var contentArray = Array(content)
            CMSEncoderUpdateContent(cmsEncoder, &contentArray, content.count)

            var signature: CFData?
            status = CMSEncoderCopyEncodedContent(cmsEncoder, &signature)
            guard status == errSecSuccess, let signature = signature else {
                throw SigningError.signingFailed("Signing failed. Error: \(status)")
            }

            return signature as Data
        } else {
            fatalError("TO BE IMPLEMENTED")
        }
        #else
        fatalError("TO BE IMPLEMENTED")
        #endif
    }

    func status(
        of signature: Data,
        for content: Data,
        observabilityScope: ObservabilityScope
    ) async throws -> SignatureStatus {
        #if os(macOS)
        var cmsDecoder: CMSDecoder?
        var status = CMSDecoderCreate(&cmsDecoder)
        guard status == errSecSuccess, let cmsDecoder = cmsDecoder else {
            throw SigningError.decodeInitializationFailed("Unable to create CMSDecoder. Error: \(status)")
        }

        CMSDecoderSetDetachedContent(cmsDecoder, content as CFData)

        status = CMSDecoderUpdateMessage(cmsDecoder, [UInt8](signature), signature.count)
        guard status == errSecSuccess else {
            return .invalid("Unable to update CMSDecoder with signature. Error: \(status)")
        }
        status = CMSDecoderFinalizeMessage(cmsDecoder)
        guard status == errSecSuccess else {
            return .invalid("Failed to set up CMSDecoder. Error: \(status)")
        }

        var signerStatus = CMSSignerStatus.needsDetachedContent
        var certificateVerifyResult: OSStatus = errSecSuccess
        var trust: SecTrust?

        // TODO: build policy based on user config
        let basicPolicy = SecPolicyCreateBasicX509()
        let revocationPolicy = SecPolicyCreateRevocation(kSecRevocationOCSPMethod)
        CMSDecoderCopySignerStatus(
            cmsDecoder,
            0,
            [basicPolicy, revocationPolicy] as CFArray,
            true,
            &signerStatus,
            &trust,
            &certificateVerifyResult
        )

        guard certificateVerifyResult == errSecSuccess else {
            return .certificateInvalid("Certificate verify result: \(certificateVerifyResult)")
        }
        guard signerStatus == .valid else {
            return .invalid("Signer status: \(signerStatus)")
        }

        guard let trust = trust else {
            return .certificateNotTrusted
        }

        // TODO: user configured trusted roots
        SecTrustSetNetworkFetchAllowed(trust, true)
        //        SecTrustSetAnchorCertificates(trust, trustedCAs as CFArray)
        //        SecTrustSetAnchorCertificatesOnly(trust, true)

        guard SecTrustEvaluateWithError(trust, nil) else {
            return .certificateNotTrusted
        }

        var revocationStatus: Certificate.RevocationStatus?
        if let trustResult = SecTrustCopyResult(trust) as? [String: Any],
           let trustRevocationChecked = trustResult[kSecTrustRevocationChecked as String] as? Bool
        {
            revocationStatus = trustRevocationChecked ? .valid : .revoked
        }
        observabilityScope.emit(debug: "Certificate revocation status: \(String(describing: revocationStatus))")

        return .valid
        #else
        fatalError("TO BE IMPLEMENTED")
        #endif
    }

    func signingEntity(of signature: Data) throws -> SigningEntity {
        #if os(macOS)
        var cmsDecoder: CMSDecoder?
        var status = CMSDecoderCreate(&cmsDecoder)
        guard status == errSecSuccess, let cmsDecoder = cmsDecoder else {
            throw SigningError.decodeInitializationFailed("Unable to create CMSDecoder. Error: \(status)")
        }

        status = CMSDecoderUpdateMessage(cmsDecoder, [UInt8](signature), signature.count)
        guard status == errSecSuccess else {
            throw SigningError
                .decodeInitializationFailed("Unable to update CMSDecoder with signature. Error: \(status)")
        }
        status = CMSDecoderFinalizeMessage(cmsDecoder)
        guard status == errSecSuccess else {
            throw SigningError.decodeInitializationFailed("Failed to set up CMSDecoder. Error: \(status)")
        }

        var certificate: SecCertificate?
        status = CMSDecoderCopySignerCert(cmsDecoder, 0, &certificate)
        guard status == errSecSuccess, let certificate = certificate else {
            throw SigningError.signatureInvalid("Unable to extract signing certificate. Error: \(status)")
        }

        return SigningEntity(certificate: certificate)
        #else
        // TODO: decode `data` by `format`, then construct `signedBy` from signing cert
        fatalError("TO BE IMPLEMENTED")
        #endif
    }

    private func validate(identity: SigningIdentity) throws {
        switch self.format {
        case .cms_1_0_0:
            // TODO: key must be EC
            ()
        }
    }
}
