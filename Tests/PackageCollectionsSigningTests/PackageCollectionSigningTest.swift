//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
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
@testable import PackageCollectionsSigning
import SPMTestSupport
import TSCBasic
import XCTest

class PackageCollectionSigningTests: XCTestCase {
    func test_RSA_signAndValidate_happyCase() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            let certPath = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "Test_rsa_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))
            // Trust the self-signed root cert
            let certPolicy = TestCertificatePolicy(anchorCerts: [rootCA])
            let signing = PackageCollectionSigning(certPolicy: certPolicy, callbackQueue: callbackQueue)

            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: .custom, callback: callback)
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in signing.validate(signedCollection: signedCollection, certPolicyKey: .custom, callback: callback) })
        }
    }

    func test_RSA_signAndValidate_collectionMismatch() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
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

            let certPath = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "Test_rsa_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))
            // Trust the self-signed root cert
            let certPolicy = TestCertificatePolicy(anchorCerts: [rootCA])
            let signing = PackageCollectionSigning(certPolicy: certPolicy, callbackQueue: callbackQueue)

            // Sign collection1
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection1, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: .custom, callback: callback)
            }
            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(collection: collection2, signature: signedCollection.signature)

            // The signature should be invalid
            XCTAssertThrowsError(
                try tsc_await { callback in
                    signing.validate(signedCollection: badSignedCollection, certPolicyKey: .custom, callback: callback)
                }) { error in
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }

    func test_EC_signAndValidate_happyCase() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            let certPath = fixturePath.appending(components: "Signing", "Test_ec.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "Test_ec_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))
            // Trust the self-signed root cert
            let certPolicy = TestCertificatePolicy(anchorCerts: [rootCA])
            let signing = PackageCollectionSigning(certPolicy: certPolicy, callbackQueue: callbackQueue)

            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: .custom, callback: callback)
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in signing.validate(signedCollection: signedCollection, certPolicyKey: .custom, callback: callback) })
        }
    }

    func test_EC_signAndValidate_collectionMismatch() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
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

            let certPath = fixturePath.appending(components: "Signing", "Test_ec.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "Test_ec_key.pem")

            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))
            // Trust the self-signed root cert
            let certPolicy = TestCertificatePolicy(anchorCerts: [rootCA])
            let signing = PackageCollectionSigning(certPolicy: certPolicy, callbackQueue: callbackQueue)

            // Sign collection1
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection1, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: .custom, callback: callback)
            }
            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(collection: collection2, signature: signedCollection.signature)

            // The signature should be invalid
            XCTAssertThrowsError(
                try tsc_await { callback in
                    signing.validate(signedCollection: badSignedCollection, certPolicyKey: .custom, callback: callback)
                }) { error in
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

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCAData: Data = try localFileSystem.readFileContents(rootCAPath)
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "development-key.pem")
            let certPolicyKey: CertificatePolicyKey = .default

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            do {
                let signing = PackageCollectionSigning(callbackQueue: callbackQueue)
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

            // Try passing in the cert with `additionalTrustedRootCerts` even though it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
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
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Specify `trustedRootCertsDir`
                do {
                    let signing = PackageCollectionSigning(trustedRootCertsDir: tmp.asURL, callbackQueue: callbackQueue)
                    // Sign the collection
                    let signedCollection = try tsc_await { callback in
                        signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                    }

                    // Then validate that signature is valid
                    XCTAssertNoThrow(try tsc_await { callback in
                        signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                    })
                }

                // Another way is to pass in `additionalTrustedRootCerts`
                do {
                    let signing = PackageCollectionSigning(additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                                                           callbackQueue: callbackQueue)
                    // Sign the collection
                    let signedCollection = try tsc_await { callback in
                        signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                    }

                    // Then validate that signature is valid
                    XCTAssertNoThrow(try tsc_await { callback in
                        signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                    })
                }
            }
            #endif
        }
    }

    func test_signAndValidate_appleDistributionPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            // This must be an Apple Distribution cert
            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCAData: Data = try localFileSystem.readFileContents(rootCAPath)
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "development-key.pem")
            let certPolicyKey: CertificatePolicyKey = .appleDistribution

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            do {
                let signing = PackageCollectionSigning(callbackQueue: callbackQueue)
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }

            // Try passing in the cert with `additionalTrustedRootCerts` even though it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    callbackQueue: callbackQueue
                )
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Specify `trustedRootCertsDir`
                do {
                    let signing = PackageCollectionSigning(trustedRootCertsDir: tmp.asURL, callbackQueue: callbackQueue)
                    // Sign the collection
                    let signedCollection = try tsc_await { callback in
                        signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                    }

                    // Then validate that signature is valid
                    XCTAssertNoThrow(try tsc_await { callback in
                        signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                    })
                }

                // Another way is to pass in `additionalTrustedRootCerts`
                do {
                    let signing = PackageCollectionSigning(additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                                                           callbackQueue: callbackQueue)
                    // Sign the collection
                    let signedCollection = try tsc_await { callback in
                        signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                    }

                    // Then validate that signature is valid
                    XCTAssertNoThrow(try tsc_await { callback in
                        signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                    })
                }
            }
            #endif
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            // This must be an Apple Swift Package Collection cert
            let certPath = fixturePath.appending(components: "Signing", "swift_package_collection.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCA.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCAData: Data = try localFileSystem.readFileContents(rootCAPath)
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "development-key.pem")
            let certPolicyKey: CertificatePolicyKey = .appleSwiftPackageCollection

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            do {
                let signing = PackageCollectionSigning(callbackQueue: callbackQueue)
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }

            // Try passing in the cert with `additionalTrustedRootCerts` even though it's already in the default trust store
            do {
                let signing = PackageCollectionSigning(
                    additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                    callbackQueue: callbackQueue
                )
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Specify `trustedRootCertsDir`
                do {
                    let signing = PackageCollectionSigning(trustedRootCertsDir: tmp.asURL, callbackQueue: callbackQueue)
                    // Sign the collection
                    let signedCollection = try tsc_await { callback in
                        signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                    }

                    // Then validate that signature is valid
                    XCTAssertNoThrow(try tsc_await { callback in
                        signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                    })
                }

                // Another way is to pass in `additionalTrustedRootCerts`
                do {
                    let signing = PackageCollectionSigning(additionalTrustedRootCerts: [rootCAData.base64EncodedString()],
                                                           callbackQueue: callbackQueue)
                    // Sign the collection
                    let signedCollection = try tsc_await { callback in
                        signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                    }

                    // Then validate that signature is valid
                    XCTAssertNoThrow(try tsc_await { callback in
                        signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                    })
                }
            }
            #endif
        }
    }

    func test_signAndValidate_defaultPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "development-key.pem")
            let certPolicyKey: CertificatePolicyKey = .default(subjectUserID: expectedSubjectUserID)

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let signing = PackageCollectionSigning(callbackQueue: callbackQueue)
            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in
                signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
            })
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let signing = PackageCollectionSigning(trustedRootCertsDir: tmp.asURL, callbackQueue: callbackQueue)
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }
            #endif
        }
    }

    func test_signAndValidate_appleDistributionPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            // This must be an Apple Distribution cert
            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "development-key.pem")
            let certPolicyKey: CertificatePolicyKey = .appleDistribution(subjectUserID: expectedSubjectUserID)

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let signing = PackageCollectionSigning(callbackQueue: callbackQueue)
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
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let signing = PackageCollectionSigning(trustedRootCertsDir: tmp.asURL, callbackQueue: callbackQueue)
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }
            #endif
        }
    }

    func test_signAndValidate_appleSwiftPackageCollectionPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = fixturePath.appending(components: "JSON", "good.json")
            let collectionData: Data = try localFileSystem.readFileContents(collectionPath)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            // This must be an Apple Distribution cert
            let certPath = fixturePath.appending(components: "Signing", "swift_package_collection.cer")
            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCA.cer")
            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = fixturePath.appending(components: "Signing", "development-key.pem")
            let certPolicyKey: CertificatePolicyKey = .appleSwiftPackageCollection(subjectUserID: expectedSubjectUserID)

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let signing = PackageCollectionSigning(callbackQueue: callbackQueue)
            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in
                signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
            })
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let signing = PackageCollectionSigning(trustedRootCertsDir: tmp.asURL, callbackQueue: callbackQueue)
                // Sign the collection
                let signedCollection = try tsc_await { callback in
                    signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, certPolicyKey: certPolicyKey, callback: callback)
                }

                // Then validate that signature is valid
                XCTAssertNoThrow(try tsc_await { callback in
                    signing.validate(signedCollection: signedCollection, certPolicyKey: certPolicyKey, callback: callback)
                })
            }
            #endif
        }
    }
}

fileprivate extension PackageCollectionSigning  {
    init(trustedRootCertsDir: URL? = nil, additionalTrustedRootCerts: [String]? = nil, callbackQueue: DispatchQueue) {
        self.init(trustedRootCertsDir: trustedRootCertsDir, additionalTrustedRootCerts: additionalTrustedRootCerts, observabilityScope: ObservabilitySystem.NOOP, callbackQueue: callbackQueue)
    }
    init(certPolicy: CertificatePolicy, callbackQueue: DispatchQueue) {
        self.init(certPolicy: certPolicy, observabilityScope: ObservabilitySystem.NOOP, callbackQueue: callbackQueue)
    }
}
