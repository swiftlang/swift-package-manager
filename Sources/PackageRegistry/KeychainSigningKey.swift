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
import CryptoKit
import Dispatch
import Foundation
import NIOCore
import NIOSSL
import Security

struct KeychainSigningKey: NIOSSLCustomPrivateKey, Hashable {
    private static let signingQueue = DispatchQueue(label: "org.swift.swiftpm.registry-keychain-signing")

    private nonisolated(unsafe) let key: SecKey

    let signatureAlgorithms: [SignatureAlgorithm]

    init(_ key: SecKey) throws {
        self.key = key
        self.signatureAlgorithms = try Self.supportedAlgorithms(for: key)
    }

    func sign(channel: Channel, algorithm: SignatureAlgorithm, data: ByteBuffer) -> EventLoopFuture<ByteBuffer> {
        self.sign(on: channel.eventLoop, algorithm: algorithm, data: data)
    }

    func sign(
        on eventLoop: any EventLoop,
        algorithm: SignatureAlgorithm,
        data: ByteBuffer
    ) -> EventLoopFuture<ByteBuffer> {
        let promise = eventLoop.makePromise(of: ByteBuffer.self)
        let payload = Data(data.readableBytesView)

        Self.signingQueue.async {
            promise.completeWith(
                Result { ByteBuffer(bytes: try self.signature(of: payload, using: algorithm)) }
            )
        }

        return promise.futureResult
    }

    func decrypt(channel: Channel, data: ByteBuffer) -> EventLoopFuture<ByteBuffer> {
        channel.eventLoop.makeFailedFuture(KeychainTLSIdentityError.decryptionUnsupported)
    }

    static func == (lhs: KeychainSigningKey, rhs: KeychainSigningKey) -> Bool {
        CFEqual(lhs.key, rhs.key)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(self.key))
    }

    private func signature(of payload: Data, using algorithm: SignatureAlgorithm) throws -> Data {
        guard self.signatureAlgorithms.contains(algorithm), let method = Self.method(for: algorithm) else {
            throw KeychainTLSIdentityError.unsupportedSignatureAlgorithm(algorithm.rawValue)
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            self.key,
            method.secKeyAlgorithm,
            method.digest(payload) as CFData,
            &error
        ) as Data? else {
            throw KeychainTLSIdentityError.signingFailed(
                error.map { "\($0.takeRetainedValue())" } ?? "the Security framework reported no reason"
            )
        }

        return signature
    }

    private static func supportedAlgorithms(for key: SecKey) throws -> [SignatureAlgorithm] {
        guard let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              let keyType = attributes[kSecAttrKeyType as String] as? String
        else {
            throw KeychainTLSIdentityError.unreadableKeyAttributes
        }

        let candidates = try Self.candidates(
            keyType: keyType,
            sizeInBits: attributes[kSecAttrKeySizeInBits as String] as? Int
        )
        let supported = candidates.filter { algorithm in
            guard let method = Self.method(for: algorithm) else { return false }
            return SecKeyIsAlgorithmSupported(key, .sign, method.secKeyAlgorithm)
        }

        guard !supported.isEmpty else {
            throw KeychainTLSIdentityError.noSupportedSignatureAlgorithms
        }
        return supported
    }

    private static func candidates(keyType: String, sizeInBits: Int?) throws -> [SignatureAlgorithm] {
        if keyType == kSecAttrKeyTypeRSA as String {
            return [
                .rsaPssRsaeSha256, .rsaPssRsaeSha384, .rsaPssRsaeSha512,
                .rsaPkcs1Sha256, .rsaPkcs1Sha384, .rsaPkcs1Sha512,
            ]
        }

        guard keyType == kSecAttrKeyTypeECSECPrimeRandom as String else {
            throw KeychainTLSIdentityError.unsupportedKeyType(keyType)
        }

        switch sizeInBits {
        case 256: return [.ecdsaSecp256R1Sha256]
        case 384: return [.ecdsaSecp384R1Sha384]
        case 521: return [.ecdsaSecp521R1Sha512]
        default: throw KeychainTLSIdentityError.unsupportedKeySize(sizeInBits ?? 0)
        }
    }

    private static func method(for algorithm: SignatureAlgorithm) -> SigningMethod? {
        switch algorithm {
        case .rsaPkcs1Sha256:
            return SigningMethod(secKeyAlgorithm: .rsaSignatureDigestPKCS1v15SHA256, digest: Self.sha256)
        case .rsaPkcs1Sha384:
            return SigningMethod(secKeyAlgorithm: .rsaSignatureDigestPKCS1v15SHA384, digest: Self.sha384)
        case .rsaPkcs1Sha512:
            return SigningMethod(secKeyAlgorithm: .rsaSignatureDigestPKCS1v15SHA512, digest: Self.sha512)
        case .rsaPssRsaeSha256:
            return SigningMethod(secKeyAlgorithm: .rsaSignatureDigestPSSSHA256, digest: Self.sha256)
        case .rsaPssRsaeSha384:
            return SigningMethod(secKeyAlgorithm: .rsaSignatureDigestPSSSHA384, digest: Self.sha384)
        case .rsaPssRsaeSha512:
            return SigningMethod(secKeyAlgorithm: .rsaSignatureDigestPSSSHA512, digest: Self.sha512)
        case .ecdsaSecp256R1Sha256:
            return SigningMethod(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA256, digest: Self.sha256)
        case .ecdsaSecp384R1Sha384:
            return SigningMethod(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA384, digest: Self.sha384)
        case .ecdsaSecp521R1Sha512:
            return SigningMethod(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA512, digest: Self.sha512)
        default:
            return .none
        }
    }

    @Sendable
    private static func sha256(_ payload: Data) -> Data {
        Data(SHA256.hash(data: payload))
    }

    @Sendable
    private static func sha384(_ payload: Data) -> Data {
        Data(SHA384.hash(data: payload))
    }

    @Sendable
    private static func sha512(_ payload: Data) -> Data {
        Data(SHA512.hash(data: payload))
    }
}

private struct SigningMethod {
    let secKeyAlgorithm: SecKeyAlgorithm
    let digest: @Sendable (Data) -> Data
}
#endif
