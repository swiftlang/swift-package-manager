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
import X509
@testable import RegistryExample

@Suite("ClientCertificateAuthenticator")
struct ClientCertificateAuthenticatorTests {
    private func seededAuthenticator(
        _ seed: (UserRegistrar) async throws -> Void
    ) async throws -> ClientCertificateAuthenticator {
        let store = UserStore()
        try await seed(UserRegistrar(store: store, tokenGenerator: TokenGenerator { "the-token" }))
        return ClientCertificateAuthenticator(store: store)
    }

    @Test func `a certificate for a registered password user authenticates`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        let certificate = try clientCertificate(email: "mona@example.com")
        #expect(await auth.authenticate(certificate: certificate)?.value == "mona@example.com")
    }

    @Test func `a certificate for a registered token user authenticates`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: nil)
        }
        let certificate = try clientCertificate(email: "mona@example.com")
        #expect(await auth.authenticate(certificate: certificate)?.value == "mona@example.com")
    }

    @Test func `a certificate for an unregistered email does not authenticate`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        let certificate = try clientCertificate(email: "ghost@example.com")
        #expect(await auth.authenticate(certificate: certificate) == nil)
    }

    @Test func `a certificate with no extractable email does not authenticate`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        let certificate = try clientCertificate(commonName: "Mona Lisa Octocat")
        #expect(await auth.authenticate(certificate: certificate) == nil)
    }

    @Test func `the certificate email matches the registered email case-insensitively`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "harry@hogwarts.com", password: "hunter2")
        }
        let certificate = try clientCertificate(email: "Harry@Hogwarts.com")
        #expect(await auth.authenticate(certificate: certificate)?.value == "harry@hogwarts.com")
    }

    @Test func `an empty store authenticates no certificate`() async throws {
        let auth = try await seededAuthenticator { _ in }
        let certificate = try clientCertificate(email: "mona@example.com")
        #expect(await auth.authenticate(certificate: certificate) == nil)
    }

    @Test func `a certificate issued by an authority authenticates like a self-signed one`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        let certificate = try clientCertificate(email: "mona@example.com", issuedBy: try certificateAuthority())
        #expect(await auth.authenticate(certificate: certificate)?.value == "mona@example.com")
    }
}
