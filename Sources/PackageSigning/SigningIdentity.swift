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

#if canImport(Darwin)
import Security
#endif

import Basics
@_implementationOnly import Crypto
@_implementationOnly import X509

public protocol SigningIdentity {}

// MARK: - SecIdentity conformance to SigningIdentity

#if canImport(Darwin)
extension SecIdentity: SigningIdentity {}
#endif

// MARK: - SwiftSigningIdentity is created using raw private key and certificate bytes

public struct SwiftSigningIdentity: SigningIdentity {
    let certificate: Certificate
    let privateKey: Certificate.PrivateKey

    // for testing
    init(certificate: Certificate, privateKey: Certificate.PrivateKey) {
        self.certificate = certificate
        self.privateKey = privateKey
    }

    public init(
        derEncodedCertificate certificateData: Data,
        derEncodedPrivateKey privateKeyData: Data,
        privateKeyType: SigningKeyType
    ) throws {
        self.certificate = try Certificate(derEncoded: Array(certificateData))
        switch privateKeyType {
        case .p256:
            self.privateKey = try Certificate.PrivateKey(P256.Signing.PrivateKey(derRepresentation: privateKeyData))
        }
    }
}

// MARK: - SigningIdentity store

public struct SigningIdentityStore {
    private let observabilityScope: ObservabilityScope

    public init(observabilityScope: ObservabilityScope) {
        self.observabilityScope = observabilityScope
    }

    public func find(by label: String) async throws -> [SigningIdentity] {
        #if canImport(Darwin)
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
            self.observabilityScope.emit(warning: "Failed to search for '\(label)' in Keychain: status \(status)")
            return []
        }

        let certificates = result as? [SecCertificate] ?? []
        return certificates.compactMap { secCertificate in
            var identity: SecIdentity?
            let status = SecIdentityCreateWithCertificate(nil, secCertificate, &identity)
            guard status == errSecSuccess, let identity = identity else {
                self.observabilityScope
                    .emit(
                        warning: "Failed to create SecIdentity from SecCertificate[\(secCertificate)]: status \(status)"
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
