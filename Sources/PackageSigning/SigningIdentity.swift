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
              let propValueList = subjectDict[kSecPropertyKeyValue] as? [[String: Any]] else {
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
        fatalError("TO BE IMPLEMENTED")
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
    public func find(by label: String) async throws -> [SigningIdentity] {
        #if os(macOS)
        // Find in Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate, // kSecClassIdentity?
            kSecReturnRef as String: true,
            kSecAttrLabel as String: label,
            kSecAttrCanSign as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
//        var item: CFTypeRef?
//        let status = SecItemCopyMatching(getquery as CFDictionary, &item)
//        guard status == errSecSuccess else { return nil } // TODO: throw?
//        let certificate = item as! SecCertificate
//        print(certificate)
//
//        // https://developer.apple.com/documentation/security/certificate_key_and_trust_services/identities/creating_an_identity
//        var identity: SecIdentity?
//        let idStatus = SecIdentityCreateWithCertificate(nil, certificate, &identity)
//        guard idStatus == errSecSuccess else { return nil } // TODO: throw?
//        print(identity)
        
        
        return []
        #else
        return []
        #endif
    }
}
