/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import Foundation

import Basics
import PackageCollectionsModel
import TSCBasic

public struct PackageCollectionSigning {
    public typealias Model = PackageCollectionModel.V1

    private static let minimumRSAKeySizeInBits = 2048

    /// URL of the optional directory containing root certificates to be trusted.
    private let trustedRootCertsDir: URL?

    /// Dispatch queue for running async tasks
    private let queue: DispatchQueue

    /// Diagnostics engine to emit warnings and errors
    private let diagnosticsEngine: DiagnosticsEngine?

    /// Internal cache/storage of `CertificatePolicy`s
    private let certPolicies = ThreadSafeKeyValueStore<CertificatePolicyKey, CertificatePolicy>()

    public init(trustedRootCertsDir: URL? = nil, queue: DispatchQueue = DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.trustedRootCertsDir = trustedRootCertsDir
        self.queue = queue
        self.diagnosticsEngine = diagnosticsEngine
        self.certPolicies[CertificatePolicyKey.default] = DefaultCertificatePolicy(
            trustedRootCertsDir: trustedRootCertsDir,
            expectedSubjectUserID: nil,
            queue: queue,
            diagnosticsEngine: diagnosticsEngine
        )
    }

    init(certPolicy: CertificatePolicy, trustedRootCertsDir: URL? = nil, queue: DispatchQueue = DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.trustedRootCertsDir = trustedRootCertsDir
        self.queue = queue
        self.certPolicies[CertificatePolicyKey.custom] = certPolicy
        self.diagnosticsEngine = diagnosticsEngine
    }

    private func getCertificatePolicy(key: CertificatePolicyKey) throws -> CertificatePolicy {
        switch key {
        case .default(let subjectUserID):
            return self.certPolicies.memoize(key) {
                DefaultCertificatePolicy(trustedRootCertsDir: self.trustedRootCertsDir, expectedSubjectUserID: subjectUserID,
                                         queue: self.queue, diagnosticsEngine: self.diagnosticsEngine)
            }
        case .appleDistribution(let subjectUserID):
            return self.certPolicies.memoize(key) {
                AppleDeveloperCertificatePolicy(trustedRootCertsDir: self.trustedRootCertsDir, expectedSubjectUserID: subjectUserID,
                                                queue: self.queue, diagnosticsEngine: self.diagnosticsEngine)
            }
        case .custom:
            // Custom `CertificatePolicy` can be set using the internal initializer only
            guard let certPolicy = self.certPolicies[key] else {
                throw PackageCollectionSigningError.certificatePolicyNotFound
            }
            return certPolicy
        }
    }

    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - certPrivateKeyPath: Path to the private key (*.pem) of the certificate
    ///   - jsonEncoder: The `JSONEncoder` to use
    ///   - callback: The callback to invoke when the signed collection is available.
    public func sign(collection: Model.Collection,
                     certChainPaths: [URL],
                     certPrivateKeyPath: URL,
                     certPolicyKey: CertificatePolicyKey = .default,
                     jsonEncoder: JSONEncoder = JSONEncoder(),
                     callback: @escaping (Result<Model.SignedCollection, Error>) -> Void) {
        guard !certChainPaths.isEmpty else {
            return callback(.failure(PackageCollectionSigningError.emptyCertChain))
        }

        do {
            // Check that the cert is valid before we do anything
            let certChainData = try certChainPaths.map { try Data(contentsOf: $0) }
            let certChain = try certChainData.map { try Certificate(derEncoded: $0) }

            let certPolicy = try self.getCertificatePolicy(key: certPolicyKey)
            certPolicy.validate(certChain: certChain) { result in
                switch result {
                case .failure(let error):
                    return callback(.failure(error))
                case .success(let isCertChainValid):
                    guard isCertChainValid else {
                        return callback(.failure(PackageCollectionSigningError.invalidCertChain))
                    }

                    do {
                        let certificate = certChain.first! // !-safe because certChain cannot be empty at this point
                        let keyType = try certificate.keyType()

                        // Signature header
                        let signatureAlgorithm: Signature.Algorithm
                        switch keyType {
                        case .RSA:
                            signatureAlgorithm = .RS256
                        case .EC:
                            signatureAlgorithm = .ES256
                        }

                        let header = Signature.Header(
                            algorithm: signatureAlgorithm,
                            certChain: certChainData.map { $0.base64EncodedString() }
                        )

                        // Key for signing
                        let privateKeyPEM = try Data(contentsOf: certPrivateKeyPath)

                        let privateKey: PrivateKey
                        switch keyType {
                        case .RSA:
                            privateKey = try RSAPrivateKey(pem: privateKeyPEM)
                        case .EC:
                            privateKey = try ECPrivateKey(pem: privateKeyPEM)
                        }
                        try self.validateKey(privateKey)

                        // Generate the signature
                        let signatureBytes = try Signature.generate(for: collection, with: header, using: privateKey, jsonEncoder: jsonEncoder)

                        guard let signature = String(bytes: signatureBytes, encoding: .utf8) else {
                            return callback(.failure(PackageCollectionSigningError.invalidSignature))
                        }
                        guard let subject = try certificate.subject().commonName, let issuer = try certificate.issuer().commonName else {
                            return callback(.failure(PackageCollectionSigningError.missingCertInfo))
                        }

                        let collectionSignature = Model.Signature(
                            signature: signature,
                            certificate: Model.Signature.Certificate(
                                subject: Model.Signature.Certificate.Name(commonName: subject),
                                issuer: Model.Signature.Certificate.Name(commonName: issuer)
                            )
                        )
                        callback(.success(Model.SignedCollection(collection: collection, signature: collectionSignature)))
                    } catch {
                        callback(.failure(error))
                    }
                }
            }
        } catch {
            callback(.failure(error))
        }
    }

    /// Validates a signed package collection.
    ///
    /// - Parameters:
    ///   - signedCollection: The signed package collection
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - jsonDecoder: The `JSONDecoder` to use
    ///   - callback: The callback to invoke when the result is available.
    public func validate(signedCollection: Model.SignedCollection,
                         certPolicyKey: CertificatePolicyKey = .default,
                         jsonDecoder: JSONDecoder = JSONDecoder(),
                         callback: @escaping (Result<Bool, Error>) -> Void) {
        guard let signature = signedCollection.signature.signature.data(using: .utf8)?.copyBytes() else {
            return callback(.failure(PackageCollectionSigningError.invalidSignature))
        }

        do {
            // Parse the signature
            let parser = try Signature.Parser(signature)

            // Signature header contains the certificate and public key for verification
            let header = try parser.header()
            guard !header.certChain.isEmpty else {
                throw SignatureError.malformedSignature
            }

            let certChain = try header.certChain.compactMap { Data(base64Encoded: $0) }.map { try Certificate(derEncoded: $0) }
            // Make sure we restore all certs successfully
            guard certChain.count == header.certChain.count else {
                throw SignatureError.malformedSignature
            }

            // Check that the certificate is valid before we do anything
            let certPolicy = try self.getCertificatePolicy(key: certPolicyKey)
            certPolicy.validate(certChain: certChain) { result in
                switch result {
                case .failure(let error):
                    return callback(.failure(error))
                case .success(let isCertChainValid):
                    guard isCertChainValid else {
                        return callback(.failure(PackageCollectionSigningError.invalidCertChain))
                    }

                    do {
                        // Extract public key from the certificate
                        let certificate = certChain.first! // !-safe because certChain is not empty at this point
                        let publicKey = try certificate.publicKey()

                        // Verify the key was used to generate the signature
                        try parser.validate(using: publicKey)

                        // Verify the signature embedded in the signature is the same as received
                        // i.e., the signature is associated with the given collection and not another
                        let collectionFromSignature = try jsonDecoder.decode(Model.Collection.self, from: Data(parser.payload))
                        callback(.success(signedCollection.collection == collectionFromSignature))
                    } catch {
                        callback(.failure(error))
                    }
                }
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func validateKey(_ privateKey: PrivateKey) throws {
        if let rsaKey = privateKey as? RSAPrivateKey {
            guard rsaKey.sizeInBits >= Self.minimumRSAKeySizeInBits else {
                throw PackageCollectionSigningError.invalidKeySize(minimumBits: Self.minimumRSAKeySizeInBits)
            }
        }
    }
}

enum PackageCollectionSigningError: Error {
    case certificatePolicyNotFound
    case emptyCertChain
    case invalidCertChain
    case invalidSignature
    case missingCertInfo
    case invalidKeySize(minimumBits: Int)
}
