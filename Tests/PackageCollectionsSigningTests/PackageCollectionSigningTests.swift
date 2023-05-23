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
import Foundation
import PackageCollectionsModel
@testable import PackageCollectionsSigning
import SPMTestSupport
import X509
import XCTest

class PackageCollectionSigningTests: XCTestCase {
    func test_RSA_signAndValidate_happyCase() async throws {
        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "Test_rsa.cer"),
                            fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                            fixturePath.appending(components: "Certificates", "TestRootCA.cer"),
                        ]
                    },
                    keyPath: { fixturePath in fixturePath.appending(components: "Certificates", "Test_rsa_key.pem") },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(certPaths.last!).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP
            )

            // Sign the collection
            let signedCollection = try await signing.sign(
                collection: collection,
                certChainPaths: certPaths.map(\.asURL),
                certPrivateKeyPath: privateKeyPath.asURL,
                certPolicyKey: .custom
            )

            // Then validate that signature is valid
            try await signing.validate(signedCollection: signedCollection, certPolicyKey: .custom)
        }
    }

    func test_RSA_signAndValidate_collectionMismatch() async throws {
        let collection1 = PackageCollectionModel.V1.Collection(
            name: "Test Package Collection 1",
            overview: nil,
            keywords: nil,
            packages: [],
            formatVersion: .v1_0,
            revision: nil,
            generatedAt: Date(),
            generatedBy: nil
        )
        let collection2 = PackageCollectionModel.V1.Collection(
            name: "Test Package Collection 2",
            overview: nil,
            keywords: nil,
            packages: [],
            formatVersion: .v1_0,
            revision: nil,
            generatedAt: Date(),
            generatedBy: nil
        )

        try await withTemporaryDirectory { tmp in
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "Test_rsa.cer"),
                            fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                            fixturePath.appending(components: "Certificates", "TestRootCA.cer"),
                        ]
                    },
                    keyPath: { fixturePath in fixturePath.appending(components: "Certificates", "Test_rsa_key.pem") },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(certPaths.last!).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP
            )

            // Sign collection1
            let signedCollection = try await signing.sign(
                collection: collection1,
                certChainPaths: certPaths.map(\.asURL),
                certPrivateKeyPath: privateKeyPath.asURL,
                certPolicyKey: .custom
            )

            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(
                collection: collection2,
                signature: signedCollection.signature
            )

            // The signature should be invalid
            do {
                try await signing.validate(signedCollection: badSignedCollection, certPolicyKey: .custom)
                XCTFail("Expected error")
            } catch {
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }

    func test_EC_signAndValidate_happyCase() async throws {
        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                            fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                            fixturePath.appending(components: "Certificates", "TestRootCA.cer"),
                        ]
                    },
                    keyPath: { fixturePath in fixturePath.appending(components: "Certificates", "Test_ec_key.pem") },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(certPaths.last!).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP
            )

            // Sign the collection
            let signedCollection = try await signing.sign(
                collection: collection,
                certChainPaths: certPaths.map(\.asURL),
                certPrivateKeyPath: privateKeyPath.asURL,
                certPolicyKey: .custom
            )

            // Then validate that signature is valid
            try await signing.validate(signedCollection: signedCollection, certPolicyKey: .custom)
        }
    }

    func test_EC_signAndValidate_collectionMismatch() async throws {
        let collection1 = PackageCollectionModel.V1.Collection(
            name: "Test Package Collection 1",
            overview: nil,
            keywords: nil,
            packages: [],
            formatVersion: .v1_0,
            revision: nil,
            generatedAt: Date(),
            generatedBy: nil
        )
        let collection2 = PackageCollectionModel.V1.Collection(
            name: "Test Package Collection 2",
            overview: nil,
            keywords: nil,
            packages: [],
            formatVersion: .v1_0,
            revision: nil,
            generatedAt: Date(),
            generatedBy: nil
        )

        try await withTemporaryDirectory { tmp in
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                            fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                            fixturePath.appending(components: "Certificates", "TestRootCA.cer"),
                        ]
                    },
                    keyPath: { fixturePath in fixturePath.appending(components: "Certificates", "Test_ec_key.pem") },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(certPaths.last!).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP
            )

            // Sign collection1
            let signedCollection = try await signing.sign(
                collection: collection1,
                certChainPaths: certPaths.map(\.asURL),
                certPrivateKeyPath: privateKeyPath.asURL,
                certPolicyKey: .custom
            )

            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(
                collection: collection2,
                signature: signedCollection.signature
            )

            // The signature should be invalid
            do {
                try await signing.validate(signedCollection: badSignedCollection, certPolicyKey: .custom)
                XCTFail("Expected error")
            } catch {
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }

    func test_signAndValidate_defaultPolicy() async throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "development.cer"),
                            fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer"),
                            fixturePath.appending(components: "Certificates", "AppleIncRoot.cer"),
                        ]
                    },
                    keyPath: { fixturePath in
                        fixturePath.appending(components: "Certificates", "development_key.pem")
                    },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCAData: Data = try localFileSystem.readFileContents(certPaths.last!)
            let certPolicyKey: CertificatePolicyKey = .default

            // Apple root certs are in SwiftPM's default trust store
            do {
                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            // Pass in the root cert with `additionalTrustedRootCerts` even though
            // it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            // Add root cert to `trustedRootCertsDir` even though it's already in the default trust store
            do {
                let trustedRootsDirPath = tmp.appending("trusted")
                try localFileSystem.createDirectory(trustedRootsDirPath, recursive: true)

                let rootCAPath = certPaths.last!
                try localFileSystem.copy(
                    from: rootCAPath,
                    to: trustedRootsDirPath.appending(components: "AppleIncRoot.cer")
                )

                let signing = PackageCollectionSigning(
                    trustedRootCertsDir: trustedRootsDirPath.asURL,
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_rsa() async throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "swift_package_collection.cer"),
                            fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer"),
                            fixturePath.appending(components: "Certificates", "AppleIncRoot.cer"),
                        ]
                    },
                    keyPath: { fixturePath in
                        fixturePath.appending(components: "Certificates", "swift_package_collection_key.pem")
                    },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCAData: Data = try localFileSystem.readFileContents(certPaths.last!)
            let certPolicyKey: CertificatePolicyKey = .appleSwiftPackageCollection

            // Apple root certs are in SwiftPM's default trust store
            do {
                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            // Pass in the root cert with `additionalTrustedRootCerts` even though
            // it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            // Add root cert to `trustedRootCertsDir` even though it's already in the default trust store
            do {
                let trustedRootsDirPath = tmp.appending("trusted")
                try localFileSystem.createDirectory(trustedRootsDirPath, recursive: true)

                let rootCAPath = certPaths.last!
                try localFileSystem.copy(
                    from: rootCAPath,
                    to: trustedRootsDirPath.appending(components: "AppleIncRoot.cer")
                )

                let signing = PackageCollectionSigning(
                    trustedRootCertsDir: trustedRootsDirPath.asURL,
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_ec() async throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "swift_package.cer"),
                            fixturePath.appending(components: "Certificates", "AppleWWDRCAG6.cer"),
                            fixturePath.appending(components: "Certificates", "AppleRootCAG3.cer"),
                        ]
                    },
                    keyPath: { fixturePath in
                        fixturePath.appending(components: "Certificates", "swift_package_key.pem")
                    },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            let rootCAData: Data = try localFileSystem.readFileContents(certPaths.last!)
            let certPolicyKey: CertificatePolicyKey = .appleSwiftPackageCollection

            // Apple root certs are in SwiftPM's default trust store
            do {
                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            // Pass in the root cert with `additionalTrustedRootCerts` even though
            // it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            // Add root cert to `trustedRootCertsDir` even though it's already in the default trust store
            do {
                let trustedRootsDirPath = tmp.appending("trusted")
                try localFileSystem.createDirectory(trustedRootsDirPath, recursive: true)

                let rootCAPath = certPaths.last!
                try localFileSystem.copy(
                    from: rootCAPath,
                    to: trustedRootsDirPath.appending(components: "AppleIncRoot.cer")
                )

                let signing = PackageCollectionSigning(
                    trustedRootCertsDir: trustedRootsDirPath.asURL,
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }
        }
    }

    func test_signAndValidate_defaultPolicy_user() async throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "development.cer"),
                            fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer"),
                            fixturePath.appending(components: "Certificates", "AppleIncRoot.cer"),
                        ]
                    },
                    keyPath: { fixturePath in
                        fixturePath.appending(components: "Certificates", "development_key.pem")
                    },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            // Apple root certs are in SwiftPM's default trust store
            do {
                // Match subject user ID
                let certPolicyKey: CertificatePolicyKey = .default(subjectUserID: expectedSubjectUserID)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            do {
                // Match subject organizational unit
                let certPolicyKey: CertificatePolicyKey = .default(subjectOrganizationalUnit: expectedSubjectOrgUnit)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_rsa_user() async throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "swift_package_collection.cer"),
                            fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer"),
                            fixturePath.appending(components: "Certificates", "AppleIncRoot.cer"),
                        ]
                    },
                    keyPath: { fixturePath in
                        fixturePath.appending(components: "Certificates", "swift_package_collection_key.pem")
                    },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            // Apple root certs are in SwiftPM's default trust store
            do {
                // Match subject user ID
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectUserID: expectedSubjectUserID)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            do {
                // Match subject organizational unit
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectOrganizationalUnit: expectedSubjectOrgUnit)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_ec_user() async throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try await withTemporaryDirectory { tmp in
            let collection = try temp_await { callback in self.readTestPackageCollection(callback: callback) }
            let (certPaths, privateKeyPath) = try temp_await { callback in
                self.copyTestCertChainAndKey(
                    certPaths: { fixturePath in
                        [
                            fixturePath.appending(components: "Certificates", "swift_package.cer"),
                            fixturePath.appending(components: "Certificates", "AppleWWDRCAG6.cer"),
                            fixturePath.appending(components: "Certificates", "AppleRootCAG3.cer"),
                        ]
                    },
                    keyPath: { fixturePath in
                        fixturePath.appending(components: "Certificates", "swift_package_key.pem")
                    },
                    tmpDirectoryPath: tmp,
                    callback: callback
                )
            }

            // Apple root certs are in SwiftPM's default trust store
            do {
                // Match subject user ID
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectUserID: expectedSubjectUserID)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }

            do {
                // Match subject organizational unit
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectOrganizationalUnit: expectedSubjectOrgUnit)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP
                )

                // Sign the collection
                let signedCollection = try await signing.sign(
                    collection: collection,
                    certChainPaths: certPaths.map(\.asURL),
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: certPolicyKey
                )

                // Then validate that signature is valid
                try await signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey)
            }
        }
    }

    private func readTestPackageCollection(callback: (Result<PackageCollectionModel.V1.Collection, Error>) -> Void) {
        do {
            try fixture(name: "Collections", createGitRepo: false) { fixturePath in
                let jsonDecoder = JSONDecoder.makeWithDefaults()
                let collectionPath = fixturePath.appending(components: "JSON", "good.json")
                let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
                let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)
                callback(.success(collection))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func copyTestCertChainAndKey(
        certPaths: (AbsolutePath) -> [AbsolutePath],
        keyPath: (AbsolutePath) -> AbsolutePath,
        tmpDirectoryPath: AbsolutePath,
        callback: (Result<([AbsolutePath], AbsolutePath), Error>) -> Void
    ) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let certSourcePaths = certPaths(fixturePath)

                let certDirectoryPath = tmpDirectoryPath.appending("Certificates")
                try localFileSystem.createDirectory(certDirectoryPath, recursive: true)

                let certDestPaths = certPaths(tmpDirectoryPath)
                for (i, sourceCertPath) in certSourcePaths.enumerated() {
                    let destCertPath = certDestPaths[i]
                    try localFileSystem.copy(from: sourceCertPath, to: destCertPath)
                }

                let keySourcePath = keyPath(fixturePath)
                let keyDestPath = keyPath(tmpDirectoryPath)
                try localFileSystem.copy(from: keySourcePath, to: keyDestPath)

                callback(.success((certDestPaths, keyDestPath)))
            }
        } catch {
            callback(.failure(error))
        }
    }
}
