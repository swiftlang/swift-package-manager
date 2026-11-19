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
import Vapor
import X509
@testable import RegistryExample

@Suite("ClientCertificateAuthenticator as request middleware")
struct ClientCertificateRequestAuthenticationTests {
    private func request(
        _ app: Application,
        chain: X509.ValidatedCertificateChain?,
        headers: HTTPHeaders = HTTPHeaders()
    ) -> Request {
        Request(
            application: app,
            method: .POST,
            url: "/login",
            headersNoUpdate: headers,
            peerCertificateChain: chain,
            on: app.eventLoopGroup.next()
        )
    }

    private func withSeededApp(
        email: String,
        _ test: (Application, ClientCertificateAuthenticator) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        app.logger.logLevel = .warning
        do {
            _ = try await UserRegistrar(store: app.userStore).register(email: email, password: "hunter2")
            try await test(app, ClientCertificateAuthenticator(store: app.userStore))
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test func `a matching certificate logs in an authenticated user`() async throws {
        try await withSeededApp(email: "mona@example.com") { app, authenticator in
            let certificate = try clientCertificate(email: "mona@example.com")
            let req = request(app, chain: peerChain(certificate))
            try await authenticator.authenticate(request: req)
            #expect(req.auth.get(AuthenticatedUser.self)?.email.value == "mona@example.com")
        }
    }

    @Test func `a request with no certificate chain stays unauthenticated`() async throws {
        try await withSeededApp(email: "mona@example.com") { app, authenticator in
            let req = request(app, chain: nil)
            try await authenticator.authenticate(request: req)
            #expect(req.auth.get(AuthenticatedUser.self) == nil)
        }
    }

    @Test func `an unregistered certificate stays unauthenticated without throwing`() async throws {
        try await withSeededApp(email: "mona@example.com") { app, authenticator in
            let certificate = try clientCertificate(email: "ghost@example.com")
            let req = request(app, chain: peerChain(certificate))
            try await authenticator.authenticate(request: req)
            #expect(req.auth.get(AuthenticatedUser.self) == nil)
        }
    }

    @Test func `a certificate without an email subject stays unauthenticated`() async throws {
        try await withSeededApp(email: "mona@example.com") { app, authenticator in
            let certificate = try clientCertificate(commonName: "Mona Lisa Octocat")
            let req = request(app, chain: peerChain(certificate))
            try await authenticator.authenticate(request: req)
            #expect(req.auth.get(AuthenticatedUser.self) == nil)
        }
    }

    @Test func `the leaf of a longer chain establishes the identity`() async throws {
        try await withSeededApp(email: "mona@example.com") { app, authenticator in
            let leaf = try clientCertificate(email: "mona@example.com")
            let root = try clientCertificate(email: "ghost@example.com")
            let chain = X509.ValidatedCertificateChain(uncheckedCertificateChain: [leaf, root])
            let req = request(app, chain: chain)
            try await authenticator.authenticate(request: req)
            #expect(req.auth.get(AuthenticatedUser.self)?.email.value == "mona@example.com")
        }
    }
}
