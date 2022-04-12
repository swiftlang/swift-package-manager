//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data

#if os(macOS)
import Security
#elseif os(Linux) || os(Windows) || os(Android)
@_implementationOnly import CCryptoBoringSSL
#endif

#if os(macOS)
typealias Certificate = CoreCertificate
#elseif os(Linux) || os(Windows) || os(Android)
typealias Certificate = BoringSSLCertificate
#else
typealias Certificate = UnsupportedCertificate
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

#elseif os(Linux) || os(Windows) || os(Android)
final class BoringSSLCertificate {
    #if CRYPTO_v2
    typealias Pointer = OpaquePointer
    #else
    typealias Pointer = UnsafeMutablePointer<X509>
    #endif
    
    private let underlying: Pointer

    deinit {
        CCryptoBoringSSL_X509_free(self.underlying)
    }

    init(derEncoded data: Data) throws {
        let bytes = data.copyBytes()
        let x509 = try bytes.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<UInt8>) throws -> Pointer in
            var pointer = ptr.baseAddress
            guard let x509 = CCryptoBoringSSL_d2i_X509(nil, &pointer, numericCast(ptr.count)) else {
                throw CertificateError.initializationFailure
            }
            return x509
        }
        self.underlying = x509
    }

    func withUnsafeMutablePointer<R>(_ body: (Pointer) throws -> R) rethrows -> R {
        return try body(self.underlying)
    }

    func subject() throws -> CertificateName {
        guard let subject = CCryptoBoringSSL_X509_get_subject_name(self.underlying) else {
            throw CertificateError.nameExtractionFailure
        }
        return CertificateName(x509Name: subject)
    }

    func issuer() throws -> CertificateName {
        guard let issuer = CCryptoBoringSSL_X509_get_issuer_name(self.underlying) else {
            throw CertificateError.nameExtractionFailure
        }
        return CertificateName(x509Name: issuer)
    }

    func publicKey() throws -> PublicKey {
        guard let key = CCryptoBoringSSL_X509_get_pubkey(self.underlying) else {
            throw CertificateError.keyExtractionFailure
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }

        var buffer: UnsafeMutablePointer<CUnsignedChar>?
        defer { CCryptoBoringSSL_OPENSSL_free(buffer) }

        let length = CCryptoBoringSSL_i2d_PublicKey(key, &buffer)
        guard length > 0 else {
            throw CertificateError.keyExtractionFailure
        }

        let data = Data(UnsafeBufferPointer(start: buffer, count: Int(length)))

        switch try self.keyType(of: key) {
        case .RSA:
            return try BoringSSLRSAPublicKey(data: data)
        case .EC:
            return try ECPublicKey(data: data)
        }
    }

    func keyType() throws -> KeyType {
        guard let key = CCryptoBoringSSL_X509_get_pubkey(self.underlying) else {
            throw CertificateError.keyExtractionFailure
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }

        return try self.keyType(of: key)
    }

    private func keyType(of key: UnsafeMutablePointer<EVP_PKEY>) throws -> KeyType {
        let algorithm = CCryptoBoringSSL_EVP_PKEY_id(key)

        switch algorithm {
        case NID_rsaEncryption:
            return .RSA
        case NID_X9_62_id_ecPublicKey:
            return .EC
        default:
            throw CertificateError.unsupportedKeyType
        }
    }
}

private extension CertificateName {
    #if CRYPTO_v2
    typealias Pointer = OpaquePointer
    #else
    typealias Pointer = UnsafeMutablePointer<X509_NAME>
    #endif
    
    init(x509Name: Pointer) {
        func getStringValue(from name: Pointer, of nid: CInt) -> String? {
            let index = CCryptoBoringSSL_X509_NAME_get_index_by_NID(name, nid, -1)
            guard index >= 0 else {
                return nil
            }

            let entry = CCryptoBoringSSL_X509_NAME_get_entry(name, index)
            guard let data = CCryptoBoringSSL_X509_NAME_ENTRY_get_data(entry) else {
                return nil
            }

            var value: UnsafeMutablePointer<CUnsignedChar>?
            defer { CCryptoBoringSSL_OPENSSL_free(value) }

            guard CCryptoBoringSSL_ASN1_STRING_to_UTF8(&value, data) >= 0 else {
                return nil
            }

            return String.decodeCString(value, as: UTF8.self, repairingInvalidCodeUnits: true)?.result
        }

        self.userID = getStringValue(from: x509Name, of: NID_userId)
        self.commonName = getStringValue(from: x509Name, of: NID_commonName)
        self.organization = getStringValue(from: x509Name, of: NID_organizationName)
        self.organizationalUnit = getStringValue(from: x509Name, of: NID_organizationalUnitName)
    }
}

// MARK: - Certificate implementation for unsupported platforms

#else
struct UnsupportedCertificate {
    init(derEncoded data: Data) throws {
        fatalError("Unsupported: \(#function)")
    }

    func subject() throws -> CertificateName {
        fatalError("Unsupported: \(#function)")
    }

    func issuer() throws -> CertificateName {
        fatalError("Unsupported: \(#function)")
    }

    func publicKey() throws -> PublicKey {
        fatalError("Unsupported: \(#function)")
    }

    func keyType() throws -> KeyType {
        fatalError("Unsupported: \(#function)")
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
