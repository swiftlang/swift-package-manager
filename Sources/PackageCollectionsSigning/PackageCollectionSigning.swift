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


import Basics
import Dispatch
import Foundation
import PackageCollectionsModel
import SwiftASN1

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import _CryptoExtras
@_implementationOnly import Crypto
@_implementationOnly import X509
#else
import _CryptoExtras
import Crypto
import X509
#endif

public protocol PackageCollectionSigner {
    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - privateKeyPEM: Data of the private key (*.pem) of the certificate
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    func sign(
        collection: PackageCollectionModel.V1.Collection,
        certChainPaths: [URL],
        privateKeyPEM: Data,
        certPolicyKey: CertificatePolicyKey
    ) async throws -> PackageCollectionModel.V1.SignedCollection
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
    public func sign(
        collection: PackageCollectionModel.V1.Collection,
        certChainPaths: [URL],
        certPrivateKeyPath: URL,
        certPolicyKey: CertificatePolicyKey = .default
    ) async throws -> PackageCollectionModel.V1.SignedCollection {
        let privateKey = try Data(contentsOf: certPrivateKeyPath)
        return try await self.sign(
            collection: collection,
            certChainPaths: certChainPaths,
            privateKeyPEM: privateKey,
            certPolicyKey: certPolicyKey
        )
    }
}

public protocol PackageCollectionSignatureValidator {
    /// Validates a signed package collection.
    ///
    /// - Parameters:
    ///   - signedCollection: The signed package collection
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    func validate(
        signedCollection: PackageCollectionModel.V1.SignedCollection,
        certPolicyKey: CertificatePolicyKey
    ) async throws
}

// MARK: - Implementation

public actor PackageCollectionSigning: PackageCollectionSigner, PackageCollectionSignatureValidator {
    public typealias Model = PackageCollectionModel.V1

    private static let minimumRSAKeySizeInBits = 2048

    /// URL of the optional directory containing root certificates to be trusted.
    private let trustedRootCertsDir: URL?
    /// Root certificates to be trusted in additional to those found in `trustedRootCertsDir`
    private let additionalTrustedRootCerts: [Certificate]?

    /// Internal cache/storage of `CertificatePolicy`s
    private let certPolicies: [CertificatePolicyKey: CertificatePolicy]

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let observabilityScope: ObservabilityScope

    public init(
        trustedRootCertsDir: URL? = nil,
        additionalTrustedRootCerts: [String]? = nil,
        observabilityScope: ObservabilityScope
    ) {
        self.trustedRootCertsDir = trustedRootCertsDir
        self.additionalTrustedRootCerts = additionalTrustedRootCerts.map { $0.compactMap {
            guard let data = Data(base64Encoded: $0) else {
                observabilityScope.emit(error: "The certificate \($0) is not in valid base64 encoding")
                return nil
            }
            do {
                return try Certificate(derEncoded: Array(data))
            } catch {
                observabilityScope.emit(
                    error: "The certificate \($0) is not in valid DER format",
                    underlyingError: error
                )
                return nil
            }
        } }

        self.certPolicies = [:]
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
        self.observabilityScope = observabilityScope
    }

    init(certPolicy: CertificatePolicy, observabilityScope: ObservabilityScope) {
        // These should be set through the given CertificatePolicy
        self.trustedRootCertsDir = nil
        self.additionalTrustedRootCerts = nil

        self.certPolicies = [CertificatePolicyKey.custom: certPolicy]
        self.encoder = JSONEncoder.makeWithDefaults()
        self.decoder = JSONDecoder.makeWithDefaults()
        self.observabilityScope = observabilityScope
    }

    private func getCertificatePolicy(key: CertificatePolicyKey) throws -> CertificatePolicy {
        switch key {
        case .default(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return DefaultCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit,
                observabilityScope: self.observabilityScope
            )
        case .appleSwiftPackageCollection(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return ADPSwiftPackageCollectionCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit,
                observabilityScope: self.observabilityScope
            )
        case .appleDistribution(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return ADPAppleDistributionCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit,
                observabilityScope: self.observabilityScope
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
        certPolicyKey: CertificatePolicyKey = .default
    ) async throws -> Model.SignedCollection {
        let certChainData = try certChainPaths.map { try Data(contentsOf: $0) }
        // Check that the certificate is valid
        let certChain = try await self.validateCertChain(certChainData, certPolicyKey: certPolicyKey)

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
                    try privateKey.signature(for: SHA256.hash(data: $0), padding: Signature.rsaSigningPadding)
                        .rawRepresentation
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
            jsonEncoder: self.encoder,
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
        return Model.SignedCollection(collection: collection, signature: collectionSignature)
    }

    public func validate(
        signedCollection: Model.SignedCollection,
        certPolicyKey: CertificatePolicyKey = .default
    ) async throws {
        let signatureBytes = Data(signedCollection.signature.signature.utf8).copyBytes()

        // Parse the signature
        let certChainValidate = { certChainData in
            try await self.validateCertChain(certChainData, certPolicyKey: certPolicyKey)
        }
        let signature = try await Signature.parse(
            signatureBytes,
            certChainValidate: certChainValidate,
            jsonDecoder: self.decoder
        )

        // Verify the collection embedded in the signature is the same as received
        // i.e., the signature is associated with the given collection and not another
        guard let collectionFromSignature = try? self.decoder.decode(
            Model.Collection.self,
            from: signature.payload
        ),
            signedCollection.collection == collectionFromSignature
        else {
            throw PackageCollectionSigningError.invalidSignature
        }
    }

    private func validateCertChain(
        _ certChainData: [Data],
        certPolicyKey: CertificatePolicyKey
    ) async throws -> [Certificate] {
        guard !certChainData.isEmpty else {
            throw PackageCollectionSigningError.emptyCertChain
        }

        do {
            let certChain = try certChainData.map { try Certificate(derEncoded: Array($0)) }
            let certPolicy = try self.getCertificatePolicy(key: certPolicyKey)

            do {
                try await certPolicy.validate(certChain: certChain)
                return certChain
            } catch {
                self.observabilityScope.emit(
                    error: "\(certPolicyKey): The certificate chain is invalid",
                    underlyingError: error
                )

                if CertificatePolicyError.noTrustedRootCertsConfigured == error as? CertificatePolicyError {
                    throw PackageCollectionSigningError.noTrustedRootCertsConfigured
                } else {
                    throw PackageCollectionSigningError.invalidCertChain
                }
            }
        } catch let error as PackageCollectionSigningError {
            throw error
        } catch {
            self.observabilityScope.emit(
                error: "An error has occurred while validating certificate chain",
                underlyingError: error
            )
            throw PackageCollectionSigningError.invalidCertChain
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
