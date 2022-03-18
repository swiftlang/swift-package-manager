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
@testable import PackageCollectionsSigning
import SPMTestSupport
import TSCBasic
import XCTest

class CertificatePolicyTests: XCTestCase {
    func test_RSA_validate_happyCase() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            let policy = TestCertificatePolicy(anchorCerts: [rootCA])
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
        }
    }

    func test_EC_validate_happyCase() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "Test_ec.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            let policy = TestCertificatePolicy(anchorCerts: [rootCA])
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
        }
    }

    func test_validate_untrustedRoot() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            // Self-signed root is not trusted
            let policy = TestCertificatePolicy(anchorCerts: [])
            XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                #if os(macOS)
                guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                }
                #elseif os(Linux) || os(Windows) || os(Android)
                guard CertificatePolicyError.noTrustedRootCertsConfigured == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.noTrustedRootCertsConfigured")
                }
                #endif
            }
        }
    }

    func test_validate_expiredCert() throws {
        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "Test_rsa.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "TestIntermediateCA.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "TestRootCA.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            // Use verify date outside of cert's validity period
            let policy = TestCertificatePolicy(anchorCerts: [rootCA], verifyDate: TestCertificatePolicy.testCertInvalidDate)
            XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                }
            }
        }
    }

    func test_validate_revoked() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "development-revoked.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let policy = DefaultCertificatePolicy(
                trustedRootCertsDir: nil, additionalTrustedRootCerts: nil,
                callbackQueue: callbackQueue
            )
            XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                }
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil,
                                                      callbackQueue: callbackQueue)
                XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }
            #endif
        }
    }

    func test_validate_defaultPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            do {
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil, additionalTrustedRootCerts: nil,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }

            // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
            do {
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil, additionalTrustedRootCerts: [rootCA],
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Specify `trustedRootCertsDir`
                do {
                    let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil,
                                                          callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }

                // Another way is to pass in `additionalTrustedRootCerts`
                do {
                    let policy = DefaultCertificatePolicy(trustedRootCertsDir: nil, additionalTrustedRootCerts: [rootCA],
                                                          callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }

                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                do {
                    let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: [rootCA],
                                                          callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }
            }
            #endif
        }
    }

    func test_validate_appleSwiftPackageCollectionPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            // This must be an Apple Swift Package Collection cert
            let certPath = fixturePath.appending(components: "Signing", "swift_package_collection.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCA.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            do {
                let policy = AppleSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil, additionalTrustedRootCerts: nil,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }

            // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
            do {
                let policy = AppleSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil, additionalTrustedRootCerts: [rootCA],
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Specify `trustedRootCertsDir`
                do {
                    let policy = AppleSwiftPackageCollectionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil,
                                                                              callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }

                // Another way is to pass in `additionalTrustedRootCerts`
                do {
                    let policy = AppleSwiftPackageCollectionCertificatePolicy(trustedRootCertsDir: nil, additionalTrustedRootCerts: [rootCA],
                                                                              callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }

                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                do {
                    let policy = AppleSwiftPackageCollectionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: [rootCA],
                                                                              callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }
            }
            #endif
        }
    }

    func test_validate_appleDistributionPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            // This must be an Apple Distribution cert
            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            do {
                let policy = AppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil, additionalTrustedRootCerts: nil,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }

            // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
            do {
                let policy = AppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil, additionalTrustedRootCerts: [rootCA],
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Specify `trustedRootCertsDir`
                do {
                    let policy = AppleDistributionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil,
                                                                    callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }

                // Another way is to pass in `additionalTrustedRootCerts`
                do {
                    let policy = AppleDistributionCertificatePolicy(trustedRootCertsDir: nil, additionalTrustedRootCerts: [rootCA],
                                                                    callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }

                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                do {
                    let policy = AppleDistributionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: [rootCA],
                                                                    callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }
            }
            #endif
        }
    }

    func test_validate_defaultPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted

            // Subject user ID matches
            do {
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            // Subject user ID does not match
            do {
                let mismatchSubjectUserID = "\(expectedSubjectUserID)-2"
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: mismatchSubjectUserID,
                    callbackQueue: callbackQueue
                )
                XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                    guard CertificatePolicyError.subjectUserIDMismatch == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.subjectUserIDMismatch")
                    }
                }
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Subject user ID matches
                do {
                    let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil, expectedSubjectUserID: expectedSubjectUserID,
                                                          callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }
                // Subject user ID does not match
                do {
                    let mismatchSubjectUserID = "\(expectedSubjectUserID)-2"
                    let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil, expectedSubjectUserID: mismatchSubjectUserID,
                                                          callbackQueue: callbackQueue)
                    XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                        guard CertificatePolicyError.subjectUserIDMismatch == error as? CertificatePolicyError else {
                            return XCTFail("Expected CertificatePolicyError.subjectUserIDMismatch")
                        }
                    }
                }
            }
            #endif
        }
    }

    func test_validate_appleSwiftPackageCollectionPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            // This must be an Apple Swift Package Collection cert
            let certPath = fixturePath.appending(components: "Signing", "swift_package_collection.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCA.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted

            // Subject user ID matches
            do {
                let policy = AppleSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            // Subject user ID does not match
            do {
                let mismatchSubjectUserID = "\(expectedSubjectUserID)-2"
                let policy = AppleSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: mismatchSubjectUserID,
                    callbackQueue: callbackQueue
                )
                XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                    guard CertificatePolicyError.subjectUserIDMismatch == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.subjectUserIDMismatch")
                    }
                }
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Subject user ID matches
                do {
                    let policy = AppleSwiftPackageCollectionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil,
                                                                              expectedSubjectUserID: expectedSubjectUserID,
                                                                              callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }
                // Subject user ID does not match
                do {
                    let mismatchSubjectUserID = "\(expectedSubjectUserID)-2"
                    let policy = AppleSwiftPackageCollectionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil,
                                                                              expectedSubjectUserID: mismatchSubjectUserID,
                                                                              callbackQueue: callbackQueue)
                    XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                        guard CertificatePolicyError.subjectUserIDMismatch == error as? CertificatePolicyError else {
                            return XCTFail("Expected CertificatePolicyError.subjectUserIDMismatch")
                        }
                    }
                }
            }
            #endif
        }
    }

    func test_validate_appleDistributionPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try skipIfUnsupportedPlatform()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            // This must be an Apple Distribution cert
            let certPath = fixturePath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath))

            let intermediateCAPath = fixturePath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(derEncoded: try localFileSystem.readFileContents(intermediateCAPath))

            let rootCAPath = fixturePath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted

            // Subject user ID matches
            do {
                let policy = AppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            // Subject user ID does not match
            do {
                let mismatchSubjectUserID = "\(expectedSubjectUserID)-2"
                let policy = AppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: mismatchSubjectUserID,
                    callbackQueue: callbackQueue
                )
                XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                    guard CertificatePolicyError.subjectUserIDMismatch == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.subjectUserIDMismatch")
                    }
                }
            }
            #elseif os(Linux) || os(Windows) || os(Android)
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                // Subject user ID matches
                do {
                    let policy = AppleDistributionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil, expectedSubjectUserID: expectedSubjectUserID,
                                                                    callbackQueue: callbackQueue)
                    XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
                }
                // Subject user ID does not match
                do {
                    let mismatchSubjectUserID = "\(expectedSubjectUserID)-2"
                    let policy = AppleDistributionCertificatePolicy(trustedRootCertsDir: tmp.asURL, additionalTrustedRootCerts: nil, expectedSubjectUserID: mismatchSubjectUserID,
                                                                    callbackQueue: callbackQueue)
                    XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                        guard CertificatePolicyError.subjectUserIDMismatch == error as? CertificatePolicyError else {
                            return XCTFail("Expected CertificatePolicyError.subjectUserIDMismatch")
                        }
                    }
                }
            }
            #endif
        }
    }
}

fileprivate extension AppleSwiftPackageCollectionCertificatePolicy {
    init(trustedRootCertsDir: URL?, additionalTrustedRootCerts: [Certificate]?, expectedSubjectUserID: String? = nil, callbackQueue: DispatchQueue) {
        self.init(trustedRootCertsDir: trustedRootCertsDir, additionalTrustedRootCerts: additionalTrustedRootCerts, expectedSubjectUserID: expectedSubjectUserID, observabilityScope: ObservabilitySystem.NOOP, callbackQueue: callbackQueue)
    }
}

fileprivate extension AppleDistributionCertificatePolicy {
    init(trustedRootCertsDir: URL?, additionalTrustedRootCerts: [Certificate]?, expectedSubjectUserID: String? = nil, callbackQueue: DispatchQueue) {
        self.init(trustedRootCertsDir: trustedRootCertsDir, additionalTrustedRootCerts: additionalTrustedRootCerts, expectedSubjectUserID: expectedSubjectUserID, observabilityScope: ObservabilitySystem.NOOP, callbackQueue: callbackQueue)
    }
}

fileprivate extension DefaultCertificatePolicy {
    init(trustedRootCertsDir: URL?, additionalTrustedRootCerts: [Certificate]?, expectedSubjectUserID: String? = nil, callbackQueue: DispatchQueue) {
        self.init(trustedRootCertsDir: trustedRootCertsDir, additionalTrustedRootCerts: additionalTrustedRootCerts, expectedSubjectUserID: expectedSubjectUserID, observabilityScope: ObservabilitySystem.NOOP, callbackQueue: callbackQueue)
    }
}
