/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

import PackageCollectionsModel
@testable import PackageCollectionsSigning
import SPMTestSupport
import TSCBasic

class PackageCollectionSigningTests: XCTestCase {
    func test_RSA_signAndValidate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder.makeWithDefaults()
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = directoryPath.appending(components: "JSON", "good.json")
            let collectionData = Data(try localFileSystem.readFileContents(collectionPath).contents)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_rsa.cer")
            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = directoryPath.appending(components: "Signing", "Test_rsa_key.pem")

            // TODO: use TestCertificatePolicy to trust self-signed test certs
            let signing = PackageCollectionSigning()

            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, jsonEncoder: jsonEncoder, callback: callback)
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in signing.validate(signedCollection: signedCollection, jsonDecoder: jsonDecoder, callback: callback) })
        }
    }

    func test_RSA_signAndValidate_collectionMismatch() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder.makeWithDefaults()
            let jsonDecoder = JSONDecoder.makeWithDefaults()

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

            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_rsa.cer")
            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = directoryPath.appending(components: "Signing", "Test_rsa_key.pem")

            // TODO: use TestCertificatePolicy to trust self-signed test certs
            let signing = PackageCollectionSigning()

            // Sign collection1
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection1, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, jsonEncoder: jsonEncoder, callback: callback)
            }
            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(collection: collection2, signature: signedCollection.signature)

            // The signature should be invalid
            XCTAssertThrowsError(try tsc_await { callback in signing.validate(signedCollection: badSignedCollection, jsonDecoder: jsonDecoder, callback: callback) }) { error in
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }

    func test_EC_signAndValidate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder.makeWithDefaults()
            let jsonDecoder = JSONDecoder.makeWithDefaults()

            let collectionPath = directoryPath.appending(components: "JSON", "good.json")
            let collectionData = Data(try localFileSystem.readFileContents(collectionPath).contents)
            let collection = try jsonDecoder.decode(PackageCollectionModel.V1.Collection.self, from: collectionData)

            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_ec.cer")
            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = directoryPath.appending(components: "Signing", "Test_ec_key.pem")

            // TODO: use TestCertificatePolicy to trust self-signed test certs
            let signing = PackageCollectionSigning()

            // Sign the collection
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, jsonEncoder: jsonEncoder, callback: callback)
            }

            // Then validate that signature is valid
            XCTAssertNoThrow(try tsc_await { callback in signing.validate(signedCollection: signedCollection, jsonDecoder: jsonDecoder, callback: callback) })
        }
    }

    func test_EC_signAndValidate_collectionMismatch() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let jsonEncoder = JSONEncoder.makeWithDefaults()
            let jsonDecoder = JSONDecoder.makeWithDefaults()

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

            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_ec.cer")
            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let certChainPaths = [certPath, intermediateCAPath, rootCAPath].map { $0.asURL }

            let privateKeyPath = directoryPath.appending(components: "Signing", "Test_ec_key.pem")

            // TODO: use TestCertificatePolicy to trust self-signed test certs
            let signing = PackageCollectionSigning()

            // Sign collection1
            let signedCollection = try tsc_await { callback in
                signing.sign(collection: collection1, certChainPaths: certChainPaths, certPrivateKeyPath: privateKeyPath.asURL, jsonEncoder: jsonEncoder, callback: callback)
            }
            // Use collection1's signature for collection2
            let badSignedCollection = PackageCollectionModel.V1.SignedCollection(collection: collection2, signature: signedCollection.signature)

            // The signature should be invalid
            XCTAssertThrowsError(try tsc_await { callback in signing.validate(signedCollection: badSignedCollection, jsonDecoder: jsonDecoder, callback: callback) }) { error in
                guard PackageCollectionSigningError.invalidSignature == error as? PackageCollectionSigningError else {
                    return XCTFail("Expected PackageCollectionSigningError.invalidSignature")
                }
            }
        }
    }
}
