//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(macOS)
import Foundation
import NIOSSL
import Security

enum KeychainTLSIdentityError: Error, CustomStringConvertible {
    case unreadableCertificate(OSStatus)
    case unreadablePrivateKey(OSStatus)
    case unreadableKeyAttributes
    case unsupportedKeyType(String)
    case unsupportedKeySize(Int)
    case unsupportedSignatureAlgorithm(UInt16)
    case noSupportedSignatureAlgorithms
    case decryptionUnsupported
    case signingFailed(String)

    var description: String {
        switch self {
        case .unreadableCertificate(let status):
            return "The certificate of the keychain identity could not be read: \(Self.message(for: status))"
        case .unreadablePrivateKey(let status):
            return "The private key of the keychain identity could not be read: \(Self.message(for: status))"
        case .unreadableKeyAttributes:
            return "The attributes of the keychain identity's private key could not be read."
        case .unsupportedKeyType(let keyType):
            return "Keychain identities with a key of type '\(keyType)' cannot be used for mutual TLS."
        case .unsupportedKeySize(let bits):
            return "Keychain identities with a \(bits)-bit elliptic curve key cannot be used for mutual TLS."
        case .unsupportedSignatureAlgorithm(let algorithm):
            return "The keychain identity cannot sign with TLS signature algorithm 0x\(String(algorithm, radix: 16))."
        case .noSupportedSignatureAlgorithms:
            return "The keychain identity's private key supports no TLS signature algorithm."
        case .decryptionUnsupported:
            return "The keychain identity cannot be used with a cipher suite that requires RSA key exchange."
        case .signingFailed(let reason):
            return "The keychain identity failed to sign the TLS handshake: \(reason)"
        }
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
    }
}

struct KeychainTLSIdentity {
    let certificateChain: [NIOSSLCertificate]
    let privateKey: NIOSSLPrivateKey

    init(_ identity: SecIdentity, issuers: [SecCertificate] = []) throws {
        let certificate = try Self.certificate(of: identity)
        let key = try Self.privateKey(of: identity)

        self.certificateChain = try Self.chain(from: certificate, issuers: issuers).map {
            try NIOSSLCertificate(bytes: [UInt8](SecCertificateCopyData($0) as Data), format: .der)
        }
        self.privateKey = NIOSSLPrivateKey(customPrivateKey: try KeychainSigningKey(key))
    }

    private static func chain(from leaf: SecCertificate, issuers: [SecCertificate]) -> [SecCertificate] {
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([leaf] + issuers as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust
        else {
            return [leaf]
        }

        _ = SecTrustEvaluateWithError(trust, nil)
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? [leaf]
        // Drop the first cert in the chain: we know it's the root cert which is already trusted by the registry
        return [leaf] + chain.dropFirst().filter { !Self.isSelfIssued($0) }
    }

    private static func isSelfIssued(_ certificate: SecCertificate) -> Bool {
        SecCertificateCopyNormalizedIssuerSequence(certificate) as Data? ==
            SecCertificateCopyNormalizedSubjectSequence(certificate) as Data?
    }

    private static func certificate(of identity: SecIdentity) throws -> SecCertificate {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw KeychainTLSIdentityError.unreadableCertificate(status)
        }
        return certificate
    }

    private static func privateKey(of identity: SecIdentity) throws -> SecKey {
        var key: SecKey?
        let status = SecIdentityCopyPrivateKey(identity, &key)
        guard status == errSecSuccess, let key else {
            throw KeychainTLSIdentityError.unreadablePrivateKey(status)
        }
        return key
    }
}
#endif
