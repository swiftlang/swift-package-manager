/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import Foundation
import XCTest

@testable import PackageCollectionsSigning
import SPMTestSupport
import TSCBasic

class CertificatePolicyTests: XCTestCase {
    func test_RSA_validate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_rsa.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            let policy = TestCertificatePolicy(anchorCerts: [rootCA])
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
        }
    }

    func test_EC_validate_happyCase() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "Test_ec.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_ec.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            let policy = TestCertificatePolicy(anchorCerts: [rootCA])
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
        }
    }

    func test_validate_untrustedRoot() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_rsa.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            // Self-signed root is not trusted
            let policy = TestCertificatePolicy(anchorCerts: [])
            XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                }
            }
        }
    }

    func test_validate_expiredCert() throws {
        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "Test_rsa.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "TestIntermediateCA_rsa.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "TestRootCA_rsa.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

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

        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "development-revoked.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let policy = DefaultCertificatePolicy(callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
            XCTAssertThrowsError(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) }) { error in
                guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                }
            }
            #else
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
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

        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "AppleWWDRCA.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let policy = DefaultCertificatePolicy(callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            #else
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #endif
        }
    }

    func test_validate_appleDeveloperPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            // This must be an Apple Distribution cert
            let certPath = directoryPath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "AppleWWDRCA.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let policy = AppleDeveloperCertificatePolicy(callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            #else
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let policy = AppleDeveloperCertificatePolicy(trustedRootCertsDir: tmp.asURL, callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #endif
        }
    }

    func test_validate_defaultPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            let certPath = directoryPath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "AppleWWDRCA.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let policy = DefaultCertificatePolicy(expectedSubjectUserID: expectedSubjectUserID, callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            #else
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let policy = DefaultCertificatePolicy(trustedRootCertsDir: tmp.asURL, expectedSubjectUserID: expectedSubjectUserID,
                                                      callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #endif
        }
    }

    func test_validate_appleDeveloperPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        if !isSupportedPlatform {
            try XCTSkipIf(true)
        }

        fixture(name: "Collections") { directoryPath in
            // This must be an Apple Distribution cert
            let certPath = directoryPath.appending(components: "Signing", "development.cer")
            let certificate = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(certPath).contents))

            let intermediateCAPath = directoryPath.appending(components: "Signing", "AppleWWDRCA.cer")
            let intermediateCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(intermediateCAPath).contents))

            let rootCAPath = directoryPath.appending(components: "Signing", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: Data(try localFileSystem.readFileContents(rootCAPath).contents))

            let certChain = [certificate, intermediateCA, rootCA]

            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            // The Apple root certs come preinstalled on Apple platforms and they are automatically trusted
            let policy = AppleDeveloperCertificatePolicy(expectedSubjectUserID: expectedSubjectUserID, callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
            XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            #else
            // On other platforms we have to specify `trustedRootCertsDir` so the Apple root cert is trusted
            try withTemporaryDirectory { tmp in
                try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))
                let policy = AppleDeveloperCertificatePolicy(trustedRootCertsDir: tmp.asURL, expectedSubjectUserID: expectedSubjectUserID,
                                                             callbackQueue: DispatchQueue.global(), diagnosticsEngine: DiagnosticsEngine())
                XCTAssertNoThrow(try tsc_await { callback in policy.validate(certChain: certChain, callback: callback) })
            }
            #endif
        }
    }
}
