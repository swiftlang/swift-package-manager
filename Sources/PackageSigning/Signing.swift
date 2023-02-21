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
        try await identity.sign(content, in: format, observabilityScope: observabilityScope)
    }

    public func status(
        of signature: Data,
        for content: Data,
        in format: SignatureFormat,
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
