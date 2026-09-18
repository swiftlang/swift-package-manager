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

import Testing
import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import X509
@testable import RegistryExample

@Suite("Client certificate collection during the TLS handshake")
struct ClientCertificateCollectorTests {
    private func collect(_ certificates: [NIOSSLCertificate]) async throws -> NIOSSLVerificationResultWithMetadata {
        let loop = NIOSingletons.posixEventLoopGroup.next()
        let promise = loop.makePromise(of: NIOSSLVerificationResultWithMetadata.self)
        collectClientCertificateChain(certificates, promise)
        return try await promise.futureResult.get()
    }

    @Test func `a presented certificate reaches the application layer`() async throws {
        let leaf = try nioCertificate(try clientCertificate(email: "mona@example.com"))
        let result = try await collect([leaf])
        guard case let .certificateVerified(metadata) = result else {
            Issue.record("expected a presented certificate to complete the handshake")
            return
        }
        #expect(metadata.validatedCertificateChain?.leaf == leaf)
        #expect(metadata.validatedCertificateChain?.count == 1)
    }

    @Test func `the presented order is preserved so the leaf stays first`() async throws {
        let leaf = try nioCertificate(try clientCertificate(email: "mona@example.com"))
        let issuer = try nioCertificate(try clientCertificate(commonName: "Some Issuer"))
        let result = try await collect([leaf, issuer])
        guard case let .certificateVerified(metadata) = result else {
            Issue.record("expected a presented chain to complete the handshake")
            return
        }
        #expect(metadata.validatedCertificateChain?.leaf == leaf)
        #expect(metadata.validatedCertificateChain.map(Array.init) == [leaf, issuer])
    }

    @Test func `an empty chain is accepted with no chain attached`() async throws {
        let result = try await collect([])
        guard case let .certificateVerified(metadata) = result else {
            Issue.record("expected a client presenting no certificate to complete the handshake")
            return
        }
        #expect(metadata.validatedCertificateChain == nil)
    }

    @Test func `the handshake is never failed, so rejection stays an HTTP concern`() async throws {
        let leaf = try nioCertificate(try clientCertificate(commonName: "not an email"))
        #expect(try await collect([leaf]) != .failed)
        #expect(try await collect([]) != .failed)
    }
}
