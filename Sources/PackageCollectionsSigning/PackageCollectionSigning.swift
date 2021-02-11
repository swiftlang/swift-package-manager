/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

import PackageCollectionsModel

public struct PackageCollectionSigning {
    public typealias Model = PackageCollectionModel.V1

    private static let minimumRSAKeySizeInBits = 2048

    let certPolicy: CertificatePolicy

    public init() {
        self.init(certPolicy: NoopCertificatePolicy())
    }

    init(certPolicy: CertificatePolicy) {
        self.certPolicy = certPolicy
    }

    /// Signs package collection using the given certificate and key.
    ///
    /// - Parameters:
    ///   - collection: The package collection to be signed
    ///   - certChainPaths: Paths to all DER-encoded certificates in the chain. The certificate used for signing
    ///                     must be the first in the array.
    ///   - certPrivateKeyPath: Path to the private key (*.pem) of the certificate
    ///   - jsonEncoder: The `JSONEncoder` to use
    ///   - callback: The callback to invoke when the signed collection is available.
    public func sign(collection: Model.Collection,
                     certChainPaths: [URL],
                     certPrivateKeyPath: URL,
                     jsonEncoder: JSONEncoder = JSONEncoder(),
                     callback: @escaping (Result<Model.SignedCollection, Error>) -> Void) {
        do {
            let certChainData = try certChainPaths.map { try Data(contentsOf: $0) }
            // Check that the certificate is valid
            self.validateCertChain(certChainData) { result in
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
                        let signatureData = try Signature.generate(for: collection, with: header, using: privateKey, jsonEncoder: jsonEncoder)

                        guard let signature = String(bytes: signatureData, encoding: .utf8) else {
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
    ///   - jsonDecoder: The `JSONDecoder` to use
    ///   - callback: The callback to invoke when the result is available.
    public func validate(signedCollection: Model.SignedCollection,
                         jsonDecoder: JSONDecoder = JSONDecoder(),
                         callback: @escaping (Result<Void, Error>) -> Void) {
        guard let signature = signedCollection.signature.signature.data(using: .utf8)?.copyBytes() else {
            return callback(.failure(PackageCollectionSigningError.invalidSignature))
        }

        do {
            // Parse the signature
            let parser = try Signature.Parser(signature)

            // Signature header contains the certificate and public key for verification
            let header = parser.header

            let certChainData = header.certChain.compactMap { Data(base64Encoded: $0) }
            // Make sure we restore all certs successfully
            guard certChainData.count == header.certChain.count else {
                throw SignatureError.malformedSignature
            }

            // Check that the certificate is valid
            self.validateCertChain(certChainData) { result in
                switch result {
                case .failure(let error):
                    return callback(.failure(error))
                case .success(let certChain):
                    do {
                        // Extract public key from the certificate
                        let certificate = certChain.first! // !-safe because certChain is not empty at this point
                        let publicKey = try certificate.publicKey()

                        // Verify the key was used to generate the signature
                        try parser.validate(using: publicKey)

                        // Verify the signature embedded in the signature is the same as received
                        // i.e., the signature is associated with the given collection and not another
                        let collectionFromSignature = try jsonDecoder.decode(Model.Collection.self, from: parser.payload)
                        guard signedCollection.collection == collectionFromSignature else {
                            return callback(.failure(PackageCollectionSigningError.invalidSignature))
                        }
                        callback(.success(()))
                    } catch {
                        callback(.failure(error))
                    }
                }
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func validateCertChain(_ certChainData: [Data], callback: @escaping (Result<[Certificate], Error>) -> Void) {
        guard !certChainData.isEmpty else {
            return callback(.failure(PackageCollectionSigningError.emptyCertChain))
        }

        do {
            let certChain = try certChainData.map { try Certificate(derEncoded: $0) }
            self.certPolicy.validate(certChain: certChain) { result in
                switch result {
                case .failure:
                    // TODO: emit error with DiagnosticsEngine
                    callback(.failure(PackageCollectionSigningError.invalidCertChain))
                case .success:
                    callback(.success(certChain))
                }
            }
        } catch {
            // TODO: emit error with DiagnosticsEngine
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

enum PackageCollectionSigningError: Error, Equatable {
    case emptyCertChain
    case invalidCertChain
    case invalidSignature
    case missingCertInfo
    case invalidKeySize(minimumBits: Int)
}
