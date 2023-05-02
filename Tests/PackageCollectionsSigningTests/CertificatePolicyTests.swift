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
@testable import PackageCollectionsSigning
import SPMTestSupport
import X509
import XCTest

class CertificatePolicyTests: XCTestCase {
    func test_RSA_validate_happyCase() throws {
        let certChain = try temp_await { callback in self.readTestRSACertChain(callback: callback) }
        let policy = TestCertificatePolicy(trustedRoots: certChain.suffix(1))
        XCTAssertNoThrow(try temp_await { callback in policy.validate(
            certChain: certChain,
            validationTime: TestCertificatePolicy.testCertValidDate,
            callback: callback
        ) })
    }

    func test_EC_validate_happyCase() throws {
        let certChain = try temp_await { callback in self.readTestECCertChain(callback: callback) }
        let policy = TestCertificatePolicy(trustedRoots: certChain.suffix(1))
        XCTAssertNoThrow(try temp_await { callback in policy.validate(
            certChain: certChain,
            validationTime: TestCertificatePolicy.testCertValidDate,
            callback: callback
        ) })
    }

    func test_validate_untrustedRoot() throws {
        let certChain = try temp_await { callback in self.readTestRSACertChain(callback: callback) }
        // Test root is not trusted
        let policy = TestCertificatePolicy(trustedRoots: nil)
        XCTAssertThrowsError(try temp_await { callback in policy.validate(
            certChain: certChain,
            validationTime: TestCertificatePolicy.testCertValidDate,
            callback: callback
        ) }) { error in
            guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                return XCTFail("Expected CertificatePolicyError.invalidCertChain")
            }
        }
    }

    func test_validate_expiredCert() throws {
        let certChain = try temp_await { callback in self.readTestRSACertChain(callback: callback) }
        // Test root is not trusted
        let policy = TestCertificatePolicy(trustedRoots: certChain.suffix(1))

        // Use verify date outside of cert's validity period
        XCTAssertThrowsError(try temp_await { callback in policy.validate(
            certChain: certChain,
            validationTime: TestCertificatePolicy.testCertInvalidDate,
            callback: callback
        ) }) { error in
            guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                return XCTFail("Expected CertificatePolicyError.invalidCertChain")
            }
        }
    }

    func test_validate_revoked() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "development-revoked.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            // Apple root certs are in SwiftPM's default trust store
            let policy = DefaultCertificatePolicy(
                trustedRootCertsDir: nil,
                additionalTrustedRootCerts: nil,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: callbackQueue
            )

            XCTAssertThrowsError(try temp_await { callback in
                policy.validate(certChain: certChain, callback: callback)
            }) { error in
                guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                    return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                }
            }
        }
    }

    func test_validate_defaultPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "development.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: [rootCA],
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                try withTemporaryDirectory { tmp in
                    try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                    let policy = DefaultCertificatePolicy(
                        trustedRootCertsDir: tmp.asURL,
                        additionalTrustedRootCerts: [rootCA],
                        observabilityScope: ObservabilitySystem.NOOP,
                        callbackQueue: callbackQueue
                    )
                    XCTAssertNoThrow(try temp_await { callback in
                        policy.validate(certChain: certChain, callback: callback)
                    })
                }
            }
        }
    }

    func test_validate_appleSwiftPackageCollectionPolicy_rsa() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "swift_package_collection.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: [rootCA],
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                try withTemporaryDirectory { tmp in
                    try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                    let policy = ADPSwiftPackageCollectionCertificatePolicy(
                        trustedRootCertsDir: tmp.asURL,
                        additionalTrustedRootCerts: [rootCA],
                        observabilityScope: ObservabilitySystem.NOOP,
                        callbackQueue: callbackQueue
                    )
                    XCTAssertNoThrow(try temp_await { callback in
                        policy.validate(certChain: certChain, callback: callback)
                    })
                }
            }
        }
    }

    func test_validate_appleSwiftPackageCollectionPolicy_ec() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "swift_package.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG6.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleRootCAG3.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: [rootCA],
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                try withTemporaryDirectory { tmp in
                    try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                    let policy = ADPSwiftPackageCollectionCertificatePolicy(
                        trustedRootCertsDir: tmp.asURL,
                        additionalTrustedRootCerts: [rootCA],
                        observabilityScope: ObservabilitySystem.NOOP,
                        callbackQueue: callbackQueue
                    )
                    XCTAssertNoThrow(try temp_await { callback in
                        policy.validate(certChain: certChain, callback: callback)
                    })
                }
            }
        }
    }

    func test_validate_appleDistributionPolicy() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "distribution.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                let policy = ADPAppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if `additionalTrustedRootCerts` has a cert that's already in the default trust store?
                let policy = ADPAppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: [rootCA],
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )
                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // What if the same cert is in both `trustedRootCertsDir` and `additionalTrustedRootCerts`?
                try withTemporaryDirectory { tmp in
                    try localFileSystem.copy(from: rootCAPath, to: tmp.appending(components: "AppleIncRoot.cer"))

                    let policy = ADPAppleDistributionCertificatePolicy(
                        trustedRootCertsDir: tmp.asURL,
                        additionalTrustedRootCerts: [rootCA],
                        observabilityScope: ObservabilitySystem.NOOP,
                        callbackQueue: callbackQueue
                    )
                    XCTAssertNoThrow(try temp_await { callback in
                        policy.validate(certChain: certChain, callback: callback)
                    })
                }
            }
        }
    }

    func test_validate_defaultPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "development.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID matches
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID does not match
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: "\(expectedSubjectUserID)-2",
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit matches
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: expectedSubjectOrgUnit,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit does not match
                let policy = DefaultCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: "\(expectedSubjectOrgUnit)-2",
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }
        }
    }

    func test_validate_appleSwiftPackageCollectionPolicy_rsa_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "swift_package_collection.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID matches
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID does not match
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: "\(expectedSubjectUserID)-2",
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit matches
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: expectedSubjectOrgUnit,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit does not match
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: "\(expectedSubjectOrgUnit)-2",
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }
        }
    }

    func test_validate_appleSwiftPackageCollectionPolicy_ec_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "swift_package.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG6.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleRootCAG3.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID matches
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID does not match
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: "\(expectedSubjectUserID)-2",
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit matches
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: expectedSubjectOrgUnit,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit does not match
                let policy = ADPSwiftPackageCollectionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: "\(expectedSubjectOrgUnit)-2",
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }
        }
    }

    func test_validate_appleDistributionPolicy_user() throws {
        #if ENABLE_REAL_CERT_TEST
        #else
        try XCTSkipIf(true)
        #endif

        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let certPath = fixturePath.appending(components: "Certificates", "distribution.cer")
            let certificate = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

            let intermediateCAPath = fixturePath.appending(components: "Certificates", "AppleWWDRCAG3.cer")
            let intermediateCA = try Certificate(
                derEncoded: try localFileSystem.readFileContents(intermediateCAPath).contents
            )

            let rootCAPath = fixturePath.appending(components: "Certificates", "AppleIncRoot.cer")
            let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

            let certChain = [certificate, intermediateCA, rootCA]

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID matches
                let policy = ADPAppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: expectedSubjectUserID,
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject user ID does not match
                let policy = ADPAppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: "\(expectedSubjectUserID)-2",
                    expectedSubjectOrganizationalUnit: nil,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit matches
                let policy = ADPAppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: expectedSubjectOrgUnit,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertNoThrow(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                })
            }

            do {
                // Apple root certs are in SwiftPM's default trust store
                // Subject organizational unit does not match
                let policy = ADPAppleDistributionCertificatePolicy(
                    trustedRootCertsDir: nil,
                    additionalTrustedRootCerts: nil,
                    expectedSubjectUserID: nil,
                    expectedSubjectOrganizationalUnit: "\(expectedSubjectOrgUnit)-2",
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: callbackQueue
                )

                XCTAssertThrowsError(try temp_await { callback in
                    policy.validate(certChain: certChain, callback: callback)
                }) { error in
                    guard CertificatePolicyError.invalidCertChain == error as? CertificatePolicyError else {
                        return XCTFail("Expected CertificatePolicyError.invalidCertChain")
                    }
                }
            }
        }
    }

    private func readTestRSACertChain(callback: (Result<[Certificate], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let certPath = fixturePath.appending(components: "Certificates", "Test_rsa.cer")
                let leaf = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

                let intermediateCAPath = fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer")
                let intermediateCA = try Certificate(
                    derEncoded: try localFileSystem
                        .readFileContents(intermediateCAPath).contents
                )

                let rootCAPath = fixturePath.appending(components: "Certificates", "TestRootCA.cer")
                let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

                let certChain = [leaf, intermediateCA, rootCA]
                callback(.success(certChain))
            }
        } catch {
            callback(.failure(error))
        }
    }

    private func readTestECCertChain(callback: (Result<[Certificate], Error>) -> Void) {
        do {
            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                let certPath = fixturePath.appending(components: "Certificates", "Test_ec.cer")
                let leaf = try Certificate(derEncoded: try localFileSystem.readFileContents(certPath).contents)

                let intermediateCAPath = fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer")
                let intermediateCA = try Certificate(
                    derEncoded: try localFileSystem
                        .readFileContents(intermediateCAPath).contents
                )

                let rootCAPath = fixturePath.appending(components: "Certificates", "TestRootCA.cer")
                let rootCA = try Certificate(derEncoded: try localFileSystem.readFileContents(rootCAPath).contents)

                let certChain = [leaf, intermediateCA, rootCA]
                callback(.success(certChain))
            }
        } catch {
            callback(.failure(error))
        }
    }
}
