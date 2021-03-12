/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Data

#if os(macOS)
import Security
#endif

#if os(macOS)
typealias Certificate = CoreCertificate
#else
typealias Certificate = BoringSSLCertificate
#endif

// MARK: - Certificate implementation using the Security framework

#if os(macOS)
struct CoreCertificate {
    let underlying: SecCertificate

    init(derEncoded data: Data) throws {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw CertificateError.initializationFailure
        }
        self.underlying = certificate
    }

    func subject() throws -> CertificateName {
        try self.extractName(kSecOIDX509V1SubjectName)
    }

    func issuer() throws -> CertificateName {
        try self.extractName(kSecOIDX509V1IssuerName)
    }

    private func extractName(_ name: CFString) throws -> CertificateName {
        guard let dict = SecCertificateCopyValues(self.underlying, [name] as CFArray, nil) as? [CFString: Any],
            let nameDict = dict[name] as? [CFString: Any],
            let propValueList = nameDict[kSecPropertyKeyValue] as? [[String: Any]] else {
            throw CertificateError.nameExtractionFailure
        }

        let props = propValueList.reduce(into: [String: String]()) { result, item in
            if let label = item["label"] as? String, let value = item["value"] as? String {
                result[label] = value
            }
        }

        return CertificateName(
            userID: props["0.9.2342.19200300.100.1.1"], // FIXME: don't hardcode?
            commonName: props[kSecOIDCommonName as String],
            organization: props[kSecOIDOrganizationName as String],
            organizationalUnit: props[kSecOIDOrganizationalUnitName as String]
        )
    }

    func publicKey() throws -> PublicKey {
        guard let key = SecCertificateCopyKey(self.underlying) else {
            throw CertificateError.keyExtractionFailure
        }

        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw error.map { $0.takeRetainedValue() as Error } ?? CertificateError.keyExtractionFailure
        }

        switch try self.keyType(of: key) {
        case .RSA:
            return try CoreRSAPublicKey(data: data)
        case .EC:
            return try ECPublicKey(data: data)
        }
    }

    func keyType() throws -> KeyType {
        guard let key = SecCertificateCopyKey(self.underlying) else {
            throw CertificateError.keyExtractionFailure
        }
        return try self.keyType(of: key)
    }

    private func keyType(of key: SecKey) throws -> KeyType {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
            let keyType = attributes[kSecAttrKeyType] as? String else {
            throw CertificateError.indeterminateKeyType
        }

        if keyType == (kSecAttrKeyTypeRSA as String) {
            return .RSA
        } else if keyType == (kSecAttrKeyTypeEC as String) {
            return .EC
        } else {
            throw CertificateError.unsupportedKeyType
        }
    }
}

// MARK: - Certificate implementation using BoringSSL

#else
final class BoringSSLCertificate {
    init(derEncoded data: Data) throws {
        fatalError("Not implemented: \(#function)")
    }

    func subject() throws -> CertificateName {
        fatalError("Not implemented: \(#function)")
    }

    func issuer() throws -> CertificateName {
        fatalError("Not implemented: \(#function)")
    }

    func publicKey() throws -> PublicKey {
        fatalError("Not implemented: \(#function)")
    }

    func keyType() throws -> KeyType {
        fatalError("Not implemented: \(#function)")
    }
}
#endif

struct CertificateName {
    let userID: String?
    let commonName: String?
    let organization: String?
    let organizationalUnit: String?
}

enum CertificateError: Error {
    case initializationFailure
    case nameExtractionFailure
    case keyExtractionFailure
    case indeterminateKeyType
    case unsupportedKeyType
}
