//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
@testable import PackageAudit
@testable import PackageRegistry
import PackageFingerprint
import PackageSigning
import _InternalTestSupport
import Testing

import struct TSCUtility.Version

@Suite
struct RegistryAdvisorySourceTests {
    private static let registryURL = URL(string: "https://packages.example.com")!
    private let identity = PackageIdentity.plain("mona.NetKit")

    private func makeSource(
        statusCode: Int,
        body: String
    ) -> RegistryAdvisorySource {
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: Self.registryURL, supportsAvailability: false)
        let httpClient = HTTPClient { _, _ in
            .init(
                statusCode: statusCode,
                headers: .init([
                    .init(name: "Content-Type", value: "application/json"),
                    .init(name: "Content-Version", value: "1"),
                ]),
                body: Data(body.utf8)
            )
        }
        let client = RegistryClient(
            configuration: configuration,
            fingerprintStorage: MockPackageFingerprintStorage(),
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: MockPackageSigningEntityStorage(),
            signingEntityCheckingMode: .strict,
            authorizationProvider: nil,
            customHTTPClient: httpClient,
            customArchiverProvider: { _ in MockArchiver() },
            delegate: nil,
            checksumAlgorithm: MockHashAlgorithm()
        )
        return RegistryAdvisorySource(client: client, observabilityScope: ObservabilitySystem.NOOP)
    }

    private var package: AuditedPackage {
        AuditedPackage(
            identity: self.identity,
            kind: .registry(identity: self.identity, registryURL: Self.registryURL),
            state: .version(Version(1, 0, 0))
        )
    }

    @Test func decodesAdvisories() async throws {
        let source = self.makeSource(statusCode: 200, body: #"{"advisories":[{"id":"GHSA-1"}]}"#)
        let records = try await source.advisories(for: self.identity, version: Version(1, 0, 0))
        #expect(records?.map(\.id) == ["GHSA-1"])
    }

    @Test func missingEndpointIsUnsupported() async throws {
        let source = self.makeSource(statusCode: 404, body: "")
        let records = try await source.advisories(for: self.identity, version: Version(1, 0, 0))
        #expect(records == nil)
    }

    @Test func serverErrorFailsCommand() async throws {
        let source = self.makeSource(statusCode: 500, body: #"{"detail":"boom"}"#)
        let auditor = PackageAuditor(database: nil, registry: source, ignoredIDs: [])

        do {
            _ = try await auditor.audit([self.package])
            Issue.record("expected audit to throw")
        } catch let error as AuditError {
            guard case .advisorySourceFailed = error else {
                Issue.record("unexpected error \(error)")
                return
            }
            #expect(error.description.contains("mona.NetKit"))
        }
    }
}
