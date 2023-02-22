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
    // TODO: change type to Certificate
    var info: SigningIdentityInfo { get }
}

public struct SigningIdentityInfo {
    public let commonName: String?
    public let organizationalUnit: String?
    public let organization: String?

    init(commonName: String? = nil, organizationalUnit: String? = nil, organization: String? = nil) {
        self.commonName = commonName
        self.organizationalUnit = organizationalUnit
        self.organization = organization
    }
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
            organizationalUnit: props[kSecOIDOrganizationalUnitName as String],
            organization: props[kSecOIDOrganizationName as String]
        )
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
            // TODO: too restrictive to require kSecAttrCanSign == true?
//            kSecAttrCanSign as String: true,
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
