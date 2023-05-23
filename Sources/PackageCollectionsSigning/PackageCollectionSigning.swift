//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_implementationOnly import _CryptoExtras
import Basics
@_implementationOnly import Crypto
import Dispatch
import Foundation
import PackageCollectionsModel
@_implementationOnly import X509

public protocol PackageCollectionSigner {
    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - privateKeyPEM: Data of the private key (*.pem) of the certificate
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - callback: The callback to invoke when the signed collection is available.
    func sign(
        collection: PackageCollectionModel.V1.Collection,
        certChainPaths: [URL],
        privateKeyPEM: Data,
        certPolicyKey: CertificatePolicyKey,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<PackageCollectionModel.V1.SignedCollection, Error>) -> Void
    )
}

extension PackageCollectionSigner {
    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - certPrivateKeyPath: Path to the private key (*.pem) of the certificate
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - callback: The callback to invoke when the signed collection is available.
    public func sign(
        collection: PackageCollectionModel.V1.Collection,
        certChainPaths: [URL],
        certPrivateKeyPath: URL,
        certPolicyKey: CertificatePolicyKey = .default,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<PackageCollectionModel.V1.SignedCollection, Error>) -> Void
    ) {
        do {
            let privateKey = try Data(contentsOf: certPrivateKeyPath)
            self.sign(
                collection: collection,
                certChainPaths: certChainPaths,
                privateKeyPEM: privateKey,
                certPolicyKey: certPolicyKey,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                callback: callback
            )
        } catch {
            callback(.failure(error))
        }
    }
}

public protocol PackageCollectionSignatureValidator {
    /// Validates a signed package collection.
    ///
    /// - Parameters:
    ///   - signedCollection: The signed package collection
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    ///   - callback: The callback to invoke when the result is available.
    func validate(
        signedCollection: PackageCollectionModel.V1.SignedCollection,
        certPolicyKey: CertificatePolicyKey,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    )
}

// MARK: - Implementation

public struct PackageCollectionSigning: PackageCollectionSigner, PackageCollectionSignatureValidator {
    public typealias Model = PackageCollectionModel.V1

    private static let minimumRSAKeySizeInBits = 2048

    /// URL of the optional directory containing root certificates to be trusted.
    private let trustedRootCertsDir: URL?
    /// Root certificates to be trusted in additional to those found in `trustedRootCertsDir`
    private let additionalTrustedRootCerts: [Certificate]?

    /// Internal cache/storage of `CertificatePolicy`s
    private let certPolicies: [CertificatePolicyKey: CertificatePolicy]

    public init(
        trustedRootCertsDir: URL? = nil,
        additionalTrustedRootCerts: [String]? = nil
    ) {
        self.trustedRootCertsDir = trustedRootCertsDir
        self.additionalTrustedRootCerts = additionalTrustedRootCerts.map { $0.compactMap {
            guard let data = Data(base64Encoded: $0) else {
                return nil
            }
            return try? Certificate(derEncoded: Array(data))
        } }
        self.certPolicies = [:]
    }

    init(certPolicy: CertificatePolicy) {
        // These should be set through the given CertificatePolicy
        self.trustedRootCertsDir = nil
        self.additionalTrustedRootCerts = nil
        self.certPolicies = [CertificatePolicyKey.custom: certPolicy]
    }

    private func getCertificatePolicy(key: CertificatePolicyKey) throws -> CertificatePolicy {
        switch key {
        case .default(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return DefaultCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit
            )
        case .appleSwiftPackageCollection(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return ADPSwiftPackageCollectionCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit
            )
        case .appleDistribution(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return ADPAppleDistributionCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit
            )
        case .custom:
            // Custom `CertificatePolicy` can be set using the internal initializer only
            guard let certPolicy = self.certPolicies[key] else {
                throw PackageCollectionSigningError.certPolicyNotFound
            }
            return certPolicy
        }
    }

    public func sign(
        collection: Model.Collection,
        certChainPaths: [URL],
        privateKeyPEM: Data,
        certPolicyKey: CertificatePolicyKey = .default,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Model.SignedCollection, Error>) -> Void
    ) {
        do {
            let certChainData = try certChainPaths.map { try Data(contentsOf: $0) }
            // Check that the certificate is valid
            self.validateCertChain(
                certChainData,
                certPolicyKey: certPolicyKey,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue
            ) { result in
                switch result {
                case .failure(let error):
                    return callback(.failure(error))
                case .success(let certChain):
                    do {
                        let privateKeyPEMString = String(decoding: privateKeyPEM, as: UTF8.self)

                        let signatureAlgorithm: Signature.Algorithm
                        let signatureProvider: (Data) throws -> Data
                        // Determine key type
                        do {
                            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEMString)
                            signatureAlgorithm = .ES256
                            signatureProvider = {
                                try privateKey.signature(for: SHA256.hash(data: $0)).rawRepresentation
                            }
                        } catch {
                            do {
                                let privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: privateKeyPEMString)

                                guard privateKey.keySizeInBits >= Self.minimumRSAKeySizeInBits else {
                                    throw PackageCollectionSigningError
                                        .invalidKeySize(minimumBits: Self.minimumRSAKeySizeInBits)
                                }

                                signatureAlgorithm = .RS256
                                signatureProvider = {
                                    try privateKey.signature(for: SHA256.hash(data: $0), padding: Signature.rsaSigningPadding).rawRepresentation
                                }
                            } catch let error as PackageCollectionSigningError {
                                throw error
                            } catch {
                                throw PackageCollectionSigningError.unsupportedKeyType
                            }
                        }

                        // Generate signature
                        let signatureData = try Signature.generate(
                            payload: collection,
                            certChainData: certChainData,
                            jsonEncoder: JSONEncoder.makeWithDefaults(),
                            signatureAlgorithm: signatureAlgorithm,
                            signatureProvider: signatureProvider
                        )

                        guard let signature = String(bytes: signatureData, encoding: .utf8) else {
                            throw PackageCollectionSigningError.invalidSignature
                        }

                        let certificate = certChain.first! // !-safe because certChain cannot be empty at this point
                        let collectionSignature = Model.Signature(
                            signature: signature,
                            certificate: Model.Signature.Certificate(
                                subject: Model.Signature.Certificate.Name(from: certificate.subject),
                                issuer: Model.Signature.Certificate.Name(from: certificate.issuer)
                            )
                        )
                        callback(.success(
                            Model.SignedCollection(collection: collection, signature: collectionSignature)
                        ))
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
    public func validate(
        signedCollection: Model.SignedCollection,
        certPolicyKey: CertificatePolicyKey = .default,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let signature = signedCollection.signature.signature.data(using: .utf8)?.copyBytes() else {
            return callback(.failure(PackageCollectionSigningError.invalidSignature))
        }

        // Parse the signature
        let certChainValidate = { certChainData, validateCallback in
            self.validateCertChain(
                certChainData,
                certPolicyKey: certPolicyKey,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                callback: validateCallback
            )
        }
        
        let decoder = JSONDecoder.makeWithDefaults()
        Signature.parse(signature, certChainValidate: certChainValidate, jsonDecoder: decoder) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let signature):
                // Verify the collection embedded in the signature is the same as received
                // i.e., the signature is associated with the given collection and not another
                guard let collectionFromSignature = try? decoder.decode(
                    Model.Collection.self,
                    from: signature.payload
                ),
                    signedCollection.collection == collectionFromSignature
                else {
                    return callback(.failure(PackageCollectionSigningError.invalidSignature))
                }
                callback(.success(()))
            }
        }
    }

    private func validateCertChain(
        _ certChainData: [Data],
        certPolicyKey: CertificatePolicyKey,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[Certificate], Error>) -> Void
    ) {
        guard !certChainData.isEmpty else {
            return callback(.failure(PackageCollectionSigningError.emptyCertChain))
        }

        do {
            let certChain = try certChainData.map { try Certificate(derEncoded: Array($0)) }
            let certPolicy = try self.getCertificatePolicy(key: certPolicyKey)

            certPolicy.validate(certChain: certChain, observabilityScope: observabilityScope, callbackQueue: callbackQueue) { result in
                switch result {
                case .failure(let error):
                    observabilityScope.emit(
                        error: "\(certPolicyKey): The certificate chain is invalid",
                        underlyingError: error
                    )
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
            observabilityScope.emit(
                error: "An error has occurred while validating certificate chain",
                underlyingError: error
            )
            callback(.failure(PackageCollectionSigningError.invalidCertChain))
        }
    }
}

public enum PackageCollectionSigningError: Error, Equatable {
    case certPolicyNotFound
    case emptyCertChain
    case noTrustedRootCertsConfigured
    case invalidCertChain

    case invalidSignature

    case unsupportedKeyType
    case invalidKeySize(minimumBits: Int)
}

extension PackageCollectionModel.V1.Signature.Certificate.Name {
    fileprivate init(from name: DistinguishedName) {
        self.init(
            userID: name.userID,
            commonName: name.commonName,
            organizationalUnit: name.organizationalUnitName,
            organization: name.organizationName
        )
    }
}
