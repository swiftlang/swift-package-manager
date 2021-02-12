/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

#if canImport(Security)
import Security
#endif

#if canImport(Security)
typealias RSAPublicKey = CoreRSAPublicKey
typealias RSAPrivateKey = CoreRSAPrivateKey
#else
typealias RSAPublicKey = BoringSSLRSAPublicKey
typealias RSAPrivateKey = BoringSSLRSAPrivateKey
#endif

// MARK: - RSA key implementations using the Security framework

#if canImport(Security)
struct CoreRSAPrivateKey: PrivateKey {
    let underlying: SecKey

    var sizeInBits: Int {
        toBits(bytes: SecKeyGetBlockSize(self.underlying))
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let pemString = String(decoding: data, as: UTF8.self)
        let pemDocument = try ASN1.PEMDocument(pemString: pemString)
        let data = pemDocument.derBytes

        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData,
                                             options as CFDictionary,
                                             &error) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? KeyError.initializationFailure
        }

        self.underlying = key
    }
}

struct CoreRSAPublicKey: PublicKey {
    let underlying: SecKey

    var sizeInBits: Int {
        toBits(bytes: SecKeyGetBlockSize(self.underlying))
    }

    /// `data` should be in PKCS #1 format
    init(data: Data) throws {
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData,
                                             options as CFDictionary,
                                             &error) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? KeyError.initializationFailure
        }

        self.underlying = key
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        let pemString = String(decoding: data, as: UTF8.self)
        let pemDocument = try ASN1.PEMDocument(pemString: pemString)
        try self.init(data: pemDocument.derBytes)
    }
}

// MARK: - RSA key implementations using BoringSSL

#else
final class BoringSSLRSAPrivateKey: PrivateKey {
    var sizeInBits: Int {
        fatalError("Not implemented")
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        fatalError("Not implemented: \(#function)")
    }
}

final class BoringSSLRSAPublicKey: PublicKey {
    var sizeInBits: Int {
        fatalError("Not implemented")
    }

    /// `data` should be in the PKCS #1 format
    init(data: Data) throws {
        fatalError("Not implemented: \(#function)")
    }

    init<Data>(pem data: Data) throws where Data: DataProtocol {
        fatalError("Not implemented: \(#function)")
    }
}
#endif
