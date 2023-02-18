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

public protocol SigningIdentity {
    var info: SigningIdentityInfo { get }

    func sign(
        _ content: Data,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Data
}

public struct SigningIdentityInfo {
    public let commonName: String?
    public let organization: String?
    public let organizationalUnit: String?

    init(commonName: String? = nil, organization: String? = nil, organizationalUnit: String? = nil) {
        self.commonName = commonName
        self.organization = organization
        self.organizationalUnit = organizationalUnit
    }
}

public enum SigningError: Error {
    case initializationFailed(String)
    case signingFailed(String)
}

// MARK: - SecIdentity conformance to SigningIdentity

#if os(macOS)
extension SecIdentity: SigningIdentity {
    public var info: SigningIdentityInfo {
        var certificate: SecCertificate?

        let status = SecIdentityCopyCertificate(self, &certificate)
        guard status == errSecSuccess, let certificate = certificate else {
            return SigningIdentityInfo()
        }

        guard let dict = SecCertificateCopyValues(certificate, nil, nil) as? [CFString: Any],
              let subjectDict = dict[kSecOIDX509V1SubjectName] as? [CFString: Any],
              let propValueList = subjectDict[kSecPropertyKeyValue] as? [[String: Any]]
        else {
            return SigningIdentityInfo()
        }

        let props = propValueList.reduce(into: [String: String]()) { result, item in
            if let label = item["label"] as? String, let value = item["value"] as? String {
                result[label] = value
            }
        }

        return SigningIdentityInfo(
            commonName: certificate.commonName,
            organization: props[kSecOIDOrganizationName as String],
            organizationalUnit: props[kSecOIDOrganizationalUnitName as String]
        )
    }

    public func sign(
        _ content: Data,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Data {
        switch format {
        case .cms_1_0_0:
            // TODO: validate key is EC
            var cmsEncoder: CMSEncoder?
            var status = CMSEncoderCreate(&cmsEncoder)
            guard status == errSecSuccess, let cmsEncoder = cmsEncoder else {
                throw SigningError.initializationFailed("Unable to create CMSEncoder. Error: \(status)")
            }

            CMSEncoderAddSigners(cmsEncoder, self)
            CMSEncoderSetHasDetachedContent(cmsEncoder, true) // Detached signature
            CMSEncoderSetSignerAlgorithm(cmsEncoder, kCMSEncoderDigestAlgorithmSHA256)
            CMSEncoderAddSignedAttributes(cmsEncoder, CMSSignedAttributes.attrSigningTime)
//            CMSEncoderSetCertificateChainMode(cmsEncoder, .chainWithRoot)

            var contentArray = Array(content)
            CMSEncoderUpdateContent(cmsEncoder, &contentArray, content.count)

            var signature: CFData?
            status = CMSEncoderCopyEncodedContent(cmsEncoder, &signature)
            guard status == errSecSuccess, let signature = signature else {
                throw SigningError.signingFailed("Signing failed. Error: \(status)")
            }

            return signature as Data
        }
    }
}

extension SecCertificate {
    var commonName: String? {
        var commonName: CFString?
        let status = SecCertificateCopyCommonName(self, &commonName)
        guard status == errSecSuccess else { return nil }
        return commonName as String?
    }
}
#endif

// MARK: - SigningIdentity created using raw private key and certificate bytes

public struct PrivateKey {}

public struct Certificate {}

public struct SwiftSigningIdentity: SigningIdentity {
    public let key: PrivateKey
    public let certificate: Certificate

    public var info: SigningIdentityInfo {
        // TODO: read from cert
        fatalError("TO BE IMPLEMENTED")
    }

    public init(key: PrivateKey, certificate: Certificate) {
        self.key = key
        self.certificate = certificate
    }

    public func sign(
        _ content: Data,
        in format: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Data {
        fatalError("TO BE IMPLEMENTED")
    }
}

// MARK: - SigningIdentity store

public struct SigningIdentityStore {
    private let observabilityScope: ObservabilityScope

    public init(observabilityScope: ObservabilityScope) {
        self.observabilityScope = observabilityScope
    }

    public func find(by label: String) async throws -> [SigningIdentity] {
        #if os(macOS)
        // Find in Keychain
        let query: [String: Any] = [
            // Use kSecClassCertificate instead of kSecClassIdentity because the latter
            // seems to always return all results, whether matching given label or not.
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecAttrLabel as String: label,
            kSecAttrCanSign as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            self.observabilityScope.emit(warning: "Error while searching for '\(label)' in Keychain: \(status)")
            return []
        }

        let certificates = result as? [SecCertificate] ?? []
        return certificates.compactMap { secCertificate in
            var identity: SecIdentity?
            let status = SecIdentityCreateWithCertificate(nil, secCertificate, &identity)
            guard status == errSecSuccess, let identity = identity else {
                self.observabilityScope
                    .emit(
                        warning: "Error while trying to create SecIdentity from SecCertificate[\(secCertificate)]: \(status)"
                    )
                return nil
            }
            return identity
        }
        #else
        // No identity store support on other platforms
        return []
        #endif
    }
}
