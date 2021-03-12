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

public protocol PackageCollectionSigner {
    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - certPrivateKeyPath: Path to the private key (*.pem) of the certificate
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - callback: The callback to invoke when the signed collection is available.
    func sign(collection: PackageCollectionModel.V1.Collection,
              certChainPaths: [URL],
              certPrivateKeyPath: URL,
              certPolicyKey: CertificatePolicyKey,
              callback: @escaping (Result<PackageCollectionModel.V1.SignedCollection, Error>) -> Void)
}

public protocol PackageCollectionSignatureValidator {
    /// Validates a signed package collection.
    ///
    /// - Parameters:
    ///   - signedCollection: The signed package collection
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - callback: The callback to invoke when the result is available.
    func validate(signedCollection: PackageCollectionModel.V1.SignedCollection,
                  certPolicyKey: CertificatePolicyKey,
                  callback: @escaping (Result<Void, Error>) -> Void)
}

// MARK: - Implementation

public struct PackageCollectionSigning: PackageCollectionSigner, PackageCollectionSignatureValidator {
    public typealias Model = PackageCollectionModel.V1

    private static let minimumRSAKeySizeInBits = 2048

    /// URL of the optional directory containing root certificates to be trusted.
    private let trustedRootCertsDir: URL?
    /// Root certificates to be trusted in additional to those found in `trustedRootCertsDir`
    private let additionalTrustedRootCerts: [Certificate]?

    /// The `DispatchQueue` to use for callbacks
    private let callbackQueue: DispatchQueue
    /// Diagnostics engine to emit warnings and errors
    private let diagnosticsEngine: DiagnosticsEngine

    /// Internal cache/storage of `CertificatePolicy`s
    private let certPolicies: [CertificatePolicyKey: CertificatePolicy]

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(trustedRootCertsDir: URL? = nil, additionalTrustedRootCerts: [String]? = nil, callbackQueue: DispatchQueue, diagnosticsEngine: DiagnosticsEngine) {
        self.trustedRootCertsDir = trustedRootCertsDir
        self.additionalTrustedRootCerts = additionalTrustedRootCerts.map { $0.compactMap {
            guard let data = Data(base64Encoded: $0) else {
                diagnosticsEngine.emit(error: "The certificate \($0) is not in valid base64 encoding")
                return nil
            }
            do {
                return try Certificate(derEncoded: data)
            } catch {
                diagnosticsEngine.emit(error: "The certificate \($0) is not in valid DER format: \(error)")
                return nil
            }
        } }

        self.callbackQueue = callbackQueue
        self.diagnosticsEngine = diagnosticsEngine
        self.certPolicies = [:]
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    init(certPolicy: CertificatePolicy, callbackQueue: DispatchQueue, diagnosticsEngine: DiagnosticsEngine) {
        // These should be set through the given CertificatePolicy
        self.trustedRootCertsDir = nil
        self.additionalTrustedRootCerts = nil

        self.callbackQueue = callbackQueue
        self.diagnosticsEngine = diagnosticsEngine
        self.certPolicies = [CertificatePolicyKey.custom: certPolicy]
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    private func getCertificatePolicy(key: CertificatePolicyKey) throws -> CertificatePolicy {
        switch key {
        case .default(let subjectUserID):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return DefaultCertificatePolicy(trustedRootCertsDir: self.trustedRootCertsDir, additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                                            expectedSubjectUserID: subjectUserID, callbackQueue: self.callbackQueue, diagnosticsEngine: self.diagnosticsEngine)
        case .appleDistribution(let subjectUserID):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return AppleDeveloperCertificatePolicy(trustedRootCertsDir: self.trustedRootCertsDir, additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                                                   expectedSubjectUserID: subjectUserID, callbackQueue: self.callbackQueue, diagnosticsEngine: self.diagnosticsEngine)
        case .custom:
            // Custom `CertificatePolicy` can be set using the internal initializer only
            guard let certPolicy = self.certPolicies[key] else {
                throw PackageCollectionSigningError.certPolicyNotFound
            }
            return certPolicy
        }
    }

    public func sign(collection: Model.Collection,
                     certChainPaths: [URL],
                     certPrivateKeyPath: URL,
                     certPolicyKey: CertificatePolicyKey = .default,
                     callback: @escaping (Result<Model.SignedCollection, Error>) -> Void) {
        do {
            let certChainData = try certChainPaths.map { try Data(contentsOf: $0) }
            // Check that the certificate is valid
            self.validateCertChain(certChainData, certPolicyKey: certPolicyKey) { result in
                switch result {
                case .failure(let error):
                    return callback(.failure(error))
                case .success(let certChain):
                    do {
                        let certificate = certChain.first! // !-safe because certChain cannot be empty at this point
                        let keyType = try certificate.keyType()

                        // Signature header
                        let signatureAlgorithm = Signature.Algorithm.from(keyType: keyType)
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
                        let signatureData = try Signature.generate(for: collection, with: header, using: privateKey, jsonEncoder: self.encoder)

                        guard let signature = String(bytes: signatureData, encoding: .utf8) else {
                            return callback(.failure(PackageCollectionSigningError.invalidSignature))
                        }

                        let collectionSignature = Model.Signature(
                            signature: signature,
                            certificate: Model.Signature.Certificate(
                                subject: Model.Signature.Certificate.Name(from: try certificate.subject()),
                                issuer: Model.Signature.Certificate.Name(from: try certificate.issuer())
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
                         callback: @escaping (Result<Void, Error>) -> Void) {
        guard let signature = signedCollection.signature.signature.data(using: .utf8)?.copyBytes() else {
            return callback(.failure(PackageCollectionSigningError.invalidSignature))
        }

        // Parse the signature
        let certChainValidate = { certChainData, validateCallback in
            self.validateCertChain(certChainData, certPolicyKey: certPolicyKey, callback: validateCallback)
        }
        Signature.parse(signature, certChainValidate: certChainValidate, jsonDecoder: self.decoder) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let signature):
                // Verify the collection embedded in the signature is the same as received
                // i.e., the signature is associated with the given collection and not another
                guard let collectionFromSignature = try? self.decoder.decode(Model.Collection.self, from: signature.payload),
                    signedCollection.collection == collectionFromSignature else {
                    return callback(.failure(PackageCollectionSigningError.invalidSignature))
                }
                callback(.success(()))
            }
        }
    }

    private func validateCertChain(_ certChainData: [Data], certPolicyKey: CertificatePolicyKey, callback: @escaping (Result<[Certificate], Error>) -> Void) {
        guard !certChainData.isEmpty else {
            return callback(.failure(PackageCollectionSigningError.emptyCertChain))
        }

        do {
            let certChain = try certChainData.map { try Certificate(derEncoded: $0) }
            let certPolicy = try self.getCertificatePolicy(key: certPolicyKey)
            certPolicy.validate(certChain: certChain) { result in
                switch result {
                case .failure(let error):
                    self.diagnosticsEngine.emit(error: "The certificate chain is invalid: \(error)")
                    if CertificatePolicyError.noTrustedRootCertsConfigured == error as? CertificatePolicyError {
                        callback(.failure(PackageCollectionSigningError.noTrustedRootCertsConfigured))
                    } else {
                        callback(.failure(PackageCollectionSigningError.invalidCertChain))
                    }
                case .success:
                    callback(.success(certChain))
                }
            }
        } catch {
            self.diagnosticsEngine.emit(error: "An error has occurred while validating certificate chain: \(error)")
            callback(.failure(PackageCollectionSigningError.invalidCertChain))
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

public enum PackageCollectionSigningError: Error, Equatable {
    case certPolicyNotFound
    case emptyCertChain
    case noTrustedRootCertsConfigured
    case invalidCertChain
    case invalidSignature
    case missingCertInfo
    case invalidKeySize(minimumBits: Int)
}

private extension PackageCollectionModel.V1.Signature.Certificate.Name {
    init(from name: CertificateName) {
        self.init(userID: name.userID, commonName: name.commonName, organizationalUnit: name.organizationalUnit, organization: name.organization)
    }
}
