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

public struct ManifestSignature: Equatable, Codable {
    /// The signature
    public let signature: String

    /// Details about the certificate used to generate the signature
    public let certificate: Certificate

    public init(signature: String, certificate: Certificate) {
        self.signature = signature
        self.certificate = certificate
    }

    public struct Certificate: Equatable, Codable {
        /// Subject of the certificate
        public let subject: Name

        /// Issuer of the certificate
        public let issuer: Name

        /// Creates a `Certificate`
        public init(subject: Name, issuer: Name) {
            self.subject = subject
            self.issuer = issuer
        }

        /// Generic certificate name (e.g., subject, issuer)
        public struct Name: Equatable, Codable {
            /// User ID
            public let userID: String?

            /// Common name
            public let commonName: String?

            /// Organizational unit
            public let organizationalUnit: String?

            /// Organization
            public let organization: String?

            /// Creates a `Name`
            public init(
                userID: String?,
                commonName: String?,
                organizationalUnit: String?,
                organization: String?
            ) {
                self.userID = userID
                self.commonName = commonName
                self.organizationalUnit = organizationalUnit
                self.organization = organization
            }
        }
    }
}

public protocol ManifestSigner {
    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - privateKeyPEM: Data of the private key (*.pem) of the certificate
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    func sign(
        manifest: some Encodable,
        certChainPaths: [AbsolutePath],
        privateKeyPEM: Data,
        fileSystem: FileSystem,
        certPolicyKey: CertificatePolicyKey
    ) async throws -> ManifestSignature
}

extension ManifestSigner {
    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - certPrivateKeyPath: Path to the private key (*.pem) of the certificate
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    public func sign(
        manifest: some Encodable,
        certChainPaths: [AbsolutePath],
        certPrivateKeyPath: AbsolutePath,
        fileSystem: FileSystem,
        certPolicyKey: CertificatePolicyKey = .default
    ) async throws -> ManifestSignature {
        let privateKey: Data = try fileSystem.readFileContents(certPrivateKeyPath)
        return try await self.sign(
            manifest: manifest,
            certChainPaths: certChainPaths,
            privateKeyPEM: privateKey,
            fileSystem: fileSystem,
            certPolicyKey: certPolicyKey
        )
    }
}

public protocol ManifestSignatureValidator {
    /// Validates a signed package collection.
    ///
    /// - Parameters:
    ///   - signedCollection: The signed package collection
    ///   - certPolicyKey: The key of the `CertificatePolicy` to use for validating certificates
    func validate(
        manifest: any Encodable,
        signature: ManifestSignature,
        fileSystem: FileSystem,
        certPolicyKey: CertificatePolicyKey
    ) async throws
}

// MARK: - Implementation

public actor ManifestSigning: ManifestSigner, ManifestSignatureValidator {
    private static let minimumRSAKeySizeInBits = 2048

    /// Path of the optional directory containing root certificates to be trusted.
    private let trustedRootCertsDir: AbsolutePath?
    /// Root certificates to be trusted in additional to those found in `trustedRootCertsDir`
    private let additionalTrustedRootCerts: [Certificate]?

    /// Internal cache/storage of `CertificatePolicy`s
    private let certPolicies: [CertificatePolicyKey: CertificatePolicy]

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let observabilityScope: ObservabilityScope

    public init(
        trustedRootCertsDir: AbsolutePath? = nil,
        additionalTrustedRootCerts: [String]? = nil,
        observabilityScope: ObservabilityScope
    ) {
        self.trustedRootCertsDir = trustedRootCertsDir
        self.additionalTrustedRootCerts = additionalTrustedRootCerts.map {
            $0.compactMap {
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
            }
        }

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

    private func getCertificatePolicy(key: CertificatePolicyKey, fileSystem: FileSystem) throws -> CertificatePolicy {
        switch key {
        case .default(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return DefaultCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                fileSystem: fileSystem,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit,
                observabilityScope: self.observabilityScope
            )
        case .appleSwiftPackageCollection(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return ADPSwiftPackageCollectionCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                fileSystem: fileSystem,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit,
                observabilityScope: self.observabilityScope
            )
        case .appleDistribution(let subjectUserID, let subjectOrganizationalUnit):
            // Create new instance each time since contents of trustedRootCertsDir might change
            return ADPAppleDistributionCertificatePolicy(
                trustedRootCertsDir: self.trustedRootCertsDir,
                fileSystem: fileSystem,
                additionalTrustedRootCerts: self.additionalTrustedRootCerts,
                expectedSubjectUserID: subjectUserID,
                expectedSubjectOrganizationalUnit: subjectOrganizationalUnit,
                observabilityScope: self.observabilityScope
            )
        case .custom:
            // Custom `CertificatePolicy` can be set using the internal initializer only
            guard let certPolicy = self.certPolicies[key] else {
                throw ManifestSigningError.certPolicyNotFound
            }
            return certPolicy
        }
    }

    public func sign(
        manifest: some Encodable,
        certChainPaths: [AbsolutePath],
        privateKeyPEM: Data,
        fileSystem: FileSystem,
        certPolicyKey: CertificatePolicyKey = .default
    ) async throws -> ManifestSignature {
        let certChainData: [Data] = try certChainPaths.map { try fileSystem.readFileContents($0) }
        // Check that the certificate is valid
        let certChain = try await self.validateCertChain(certChainData, certPolicyKey: certPolicyKey, fileSystem: fileSystem)

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
                    throw ManifestSigningError.invalidKeySize(minimumBits: Self.minimumRSAKeySizeInBits)
                }

                signatureAlgorithm = .RS256
                signatureProvider = {
                    try privateKey.signature(for: SHA256.hash(data: $0), padding: Signature.rsaSigningPadding)
                        .rawRepresentation
                }
            } catch let error as ManifestSigningError {
                throw error
            } catch {
                throw ManifestSigningError.unsupportedKeyType
            }
        }

        // Generate signature
        let signatureData = try Signature.generate(
            payload: manifest,
            certChainData: certChainData,
            jsonEncoder: self.encoder,
            signatureAlgorithm: signatureAlgorithm,
            signatureProvider: signatureProvider
        )

        guard let signature = String(bytes: signatureData, encoding: .utf8) else {
            throw ManifestSigningError.invalidSignature
        }

        let certificate = certChain.first!  // !-safe because certChain cannot be empty at this point
        return ManifestSignature(
            signature: signature,
            certificate: ManifestSignature.Certificate(
                subject: ManifestSignature.Certificate.Name(from: certificate.subject),
                issuer: ManifestSignature.Certificate.Name(from: certificate.issuer)
            )
        )
    }

    public func validate(
        manifest: any Encodable,
        signature: ManifestSignature,
        fileSystem: FileSystem,
        certPolicyKey: CertificatePolicyKey = .default
    ) async throws {
        let signatureBytes = Data(signature.signature.utf8).copyBytes()

        // Parse the signature
        let certChainValidate = { certChainData in
            try await self.validateCertChain(certChainData, certPolicyKey: certPolicyKey, fileSystem: fileSystem)
        }
        let signature = try await Signature.parse(
            signatureBytes,
            certChainValidate: certChainValidate,
            jsonDecoder: self.decoder
        )

        // Verify the collection embedded in the signature is the same as received
        // i.e., the signature is associated with the given collection and not another
        guard try self.encoder.encode(manifest) == signature.payload else {
            throw ManifestSigningError.invalidSignature
        }
    }

    private func validateCertChain(
        _ certChainData: [Data],
        certPolicyKey: CertificatePolicyKey,
        fileSystem: FileSystem
    ) async throws -> [Certificate] {
        guard !certChainData.isEmpty else {
            throw ManifestSigningError.emptyCertChain
        }

        do {
            let certChain = try certChainData.map { try Certificate(derEncoded: Array($0)) }
            let certPolicy = try self.getCertificatePolicy(key: certPolicyKey, fileSystem: fileSystem)

            do {
                try await certPolicy.validate(certChain: certChain)
                return certChain
            } catch {
                self.observabilityScope.emit(
                    error: "\(certPolicyKey): The certificate chain is invalid",
                    underlyingError: error
                )

                if CertificatePolicyError.noTrustedRootCertsConfigured == error as? CertificatePolicyError {
                    throw ManifestSigningError.noTrustedRootCertsConfigured
                } else {
                    throw ManifestSigningError.invalidCertChain
                }
            }
        } catch let error as ManifestSigningError {
            throw error
        } catch {
            self.observabilityScope.emit(
                error: "An error has occurred while validating certificate chain",
                underlyingError: error
            )
            throw ManifestSigningError.invalidCertChain
        }
    }
}

public enum ManifestSigningError: Error, Equatable {
    case certPolicyNotFound
    case emptyCertChain
    case noTrustedRootCertsConfigured
    case invalidCertChain

    case invalidSignature

    case unsupportedKeyType
    case invalidKeySize(minimumBits: Int)
}

extension ManifestSignature.Certificate.Name {
    fileprivate init(from name: DistinguishedName) {
        self.init(
            userID: name.userID,
            commonName: name.commonName,
            organizationalUnit: name.organizationalUnitName,
            organization: name.organizationName
        )
    }
}
