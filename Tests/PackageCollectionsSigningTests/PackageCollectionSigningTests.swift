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
import TSCBasic
import X509
import XCTest

class PackageCollectionSigningTests: XCTestCase {
    func test_RSA_signAndValidate_happyCase() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "Test_rsa.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "Test_rsa_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: callbackQueue
            )

            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(
                    collection: collection,
                    certChainPaths: certChainPaths,
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: .custom,
                    callback: callback
                )
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in
                signing.validate(signedCollection: signedCollection, certPolicyKey: .custom, callback: callback)
            })
        }
    }

    func test_RSA_signAndValidate_collectionMismatch() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
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

            let certPath = fixturePath.appending(components: "Certificates", "Test_rsa.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "Test_rsa_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: callbackQueue
            )

            // Sign collection1
            let signedCollection = try tsc_await { callback in
                signing.sign(
                    collection: collection1,
                    certChainPaths: certChainPaths,
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: .custom,
                    callback: callback
                )
            }
            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(
                collection: collection2,
                signature: signedCollection.signature
            )

            // The signature should be invalid
            XCTAssertThrowsError(
                try tsc_await { callback in
                    signing.validate(signedCollection: badSignedCollection, certPolicyKey: .custom, callback: callback)
                }
            ) { error in
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }

    func test_EC_signAndValidate_happyCase() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "Test_ec.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "Test_ec_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: callbackQueue
            )

            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(
                    collection: collection,
                    certChainPaths: certChainPaths,
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: .custom,
                    callback: callback
                )
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in
                signing.validate(signedCollection: signedCollection, certPolicyKey: .custom, callback: callback)
            })
        }
    }

    func test_EC_signAndValidate_collectionMismatch() throws {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
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

            let certPath = fixturePath.appending(components: "Certificates", "Test_ec.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "Test_ec_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)
            let certPolicy = TestCertificatePolicy(trustedRoots: [rootCA])
            let signing = PackageCollectionSigning(
                certPolicy: certPolicy,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: callbackQueue
            )

            // Sign collection1
            let signedCollection = try tsc_await { callback in
                signing.sign(
                    collection: collection1,
                    certChainPaths: certChainPaths,
                    certPrivateKeyPath: privateKeyPath.asURL,
                    certPolicyKey: .custom,
                    callback: callback
                )
            }
            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(
                collection: collection2,
                signature: signedCollection.signature
            )

            // The signature should be invalid
            XCTAssertThrowsError(
                try tsc_await { callback in
                    signing.validate(signedCollection: badSignedCollection, certPolicyKey: .custom, callback: callback)
                }
            ) { error in
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }

    func test_signAndValidate_defaultPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "development.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let rootCAData: Data = try localFileSystem.readFileContents(rootCAPath)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "development_key.pem")
            let certPolicyKey: CertificatePolicyKey = .default

            // Apple root certs are in SwiftPM's default trust store
            do {
                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            // Pass in the root cert with `additionalTrustedRootCerts` even though
            // it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            // Add root cert to `trustedRootCertsDir` even though it's already in the default trust store
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                let signing = PackageCollectionSigning(
                    trustedRootCertsDir: tmp.asURL,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_rsa() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "swift_package_collection.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "swift_package_collection_key.pem")
            let certPolicyKey: CertificatePolicyKey = .appleSwiftPackageCollection

            // Apple root certs are in SwiftPM's default trust store
            do {
                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            // Add root cert to `trustedRootCertsDir` even though it's already in the default trust store
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                let signing = PackageCollectionSigning(
                    trustedRootCertsDir: tmp.asURL,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_ec() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "swift_package.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG6.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleRootCAG3.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let rootCAData: Data = try localFileSystem.readFileContents(rootCAPath)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "swift_package_key.pem")
            let certPolicyKey: CertificatePolicyKey = .appleSwiftPackageCollection

            // Apple root certs are in SwiftPM's default trust store
            do {
                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            // Pass in the root cert with `additionalTrustedRootCerts` even though
            // it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            // Add root cert to `trustedRootCertsDir` even though it's already in the default trust store
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                let signing = PackageCollectionSigning(
                    trustedRootCertsDir: tmp.asURL,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }
        }
    }

    func test_signAndValidate_defaultPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "development.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "development_key.pem")

            // Apple root certs are in SwiftPM's default trust store
            do {
                // Match subject user ID
                let certPolicyKey: CertificatePolicyKey = .default(subjectUserID: expectedSubjectUserID)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            do {
                // Match subject organizational unit
                let certPolicyKey: CertificatePolicyKey = .default(subjectOrganizationalUnit: expectedSubjectOrgUnit)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_rsa_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "swift_package_collection.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "swift_package_collection_key.pem")

            // Apple root certs are in SwiftPM's default trust store
            do {
                // Match subject user ID
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectUserID: expectedSubjectUserID)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            do {
                // Match subject organizational unit
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectOrganizationalUnit: expectedSubjectOrgUnit)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_ec_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let collection = try tsc_await { callback in self.testPackageCollection(callback: callback) }

            let certPath = fixturePath.appending(components: "Certificates", "swift_package.cer")
            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG6.cer")
            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleRootCAG3.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map(\.asURL)

            let privateKeyPath = fixturePath.appending(components: "Certificates", "swift_package_key.pem")

            // Apple root certs are in SwiftPM's default trust store
            do {
                // Match subject user ID
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectUserID: expectedSubjectUserID)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }

            do {
                // Match subject organizational unit
                let certPolicyKey: CertificatePolicyKey =
                    .appleSwiftPackageCollection(subjectOrganizationalUnit: expectedSubjectOrgUnit)

                let signing = PackageCollectionSigning(
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(
                        collection: collection,
                        certChainPaths: certChainPaths,
                        certPrivateKeyPath: privateKeyPath.asURL,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(
                        signedCollection: signedCollection,
                        certPolicyKey: certPolicyKey,
                        callback: callback
                    )
                })
            }
        }
    }

    private func testPackageCollection(callback: (Result<PackageCollectionModel.V1.Collection, Error>) -> Void) {
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
}
