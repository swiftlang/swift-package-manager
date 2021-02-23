/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import SPMTestSupport
import XCTest

@testable import PackageCollections
import PackageCollectionsSigning

final class PackageCollectionSourceCertificatePolicyTests: XCTestCase {
    func testCustomData() {
        let sourceCertPolicy = PackageCollectionSourceCertificatePolicy(sourceCertPolicies: [
            "package-collection-1": PackageCollectionSourceCertificatePolicy.CertificatePolicyConfig(
                certPolicyKey: CertificatePolicyKey.default,
                base64EncodedRootCerts: ["root-cert-1a", "root-cert-1b"]
            ),
            "package-collection-2": PackageCollectionSourceCertificatePolicy.CertificatePolicyConfig(
                certPolicyKey: CertificatePolicyKey.default,
                base64EncodedRootCerts: ["root-cert-2"]
            ),
        ])
        let source1 = Model.CollectionSource(type: .json, url: URL(string: "https://package-collection-1")!)
        let unsignedSource = Model.CollectionSource(type: .json, url: URL(string: "https://package-collection-unsigned")!)

        XCTAssertEqual(["root-cert-1a", "root-cert-1b", "root-cert-2"], sourceCertPolicy.allRootCerts?.sorted())

        XCTAssertTrue(sourceCertPolicy.mustBeSigned(source: source1))
        XCTAssertFalse(sourceCertPolicy.mustBeSigned(source: unsignedSource))

        XCTAssertEqual(CertificatePolicyKey.default, sourceCertPolicy.certificatePolicyKey(for: source1))
        XCTAssertNil(sourceCertPolicy.certificatePolicyKey(for: unsignedSource))
    }
}
