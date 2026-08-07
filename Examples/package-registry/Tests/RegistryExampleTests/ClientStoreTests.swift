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

@Suite("ClientStore")
struct ClientStoreTests {
    private func user(_ raw: String) throws -> User {
        User(email: try #require(EmailAddress(raw)), credential: .password(hash: "bcrypt"))
    }

    private func client(_ user: User, certificate: TestCertificate) throws -> Client<MutualTLS> {
        Client(
            user: user,
            auth: try MutualTLS(rootCertificateAuthority: .none, certificate: certificate.certificate())
        )
    }

    private func credentials(computedFrom certificate: TestCertificate) throws -> MutualTLS.Credentials {
        MutualTLS.Credentials(
            rootCertificateAuthority: .none,
            id: try CertificateThumbprint.of(certificate.certificate())
        )
    }

    @Test func `the certificate init derives the id from the certificate's thumbprint`() throws {
        let auth = try MutualTLS(
            rootCertificateAuthority: .none,
            certificate: harrysLaptopCertificate.certificate()
        )
        #expect(auth.credentials.id == harrysLaptopCertificate.thumbprint)
    }

    @Test func `the certificate and id inits produce the same credentials`() throws {
        let fromCertificate = try MutualTLS(
            rootCertificateAuthority: .none,
            certificate: harrysLaptopCertificate.certificate()
        )
        let fromID = MutualTLS(rootCertificateAuthority: .none, id: harrysLaptopCertificate.thumbprint)
        #expect(fromCertificate == fromID)
    }

    @Test func `round-trips a client stored under its certificate`() async throws {
        let store = ClientStore()
        let harrysLaptop = try client(try user("harry@example.com"), certificate: harrysLaptopCertificate)
        try await store.store(harrysLaptop)
        let credentials = try credentials(computedFrom: harrysLaptopCertificate)
        #expect(await store.client(ofType: MutualTLS.self, for: credentials) == harrysLaptop)
    }

    @Test func `resolves a client by a thumbprint computed independently of the store`() async throws {
        let store = ClientStore()
        let harrysLaptop = try client(try user("harry@example.com"), certificate: harrysLaptopCertificate)
        try await store.store(harrysLaptop)
        let credentials = MutualTLS.Credentials(
            rootCertificateAuthority: .none,
            id: harrysLaptopCertificate.thumbprint
        )
        #expect(await store.client(ofType: MutualTLS.self, for: credentials) == harrysLaptop)
    }

    @Test func `resolves each certificate to its own user's client`() async throws {
        let store = ClientStore()
        let harrysLaptop = try client(try user("harry@example.com"), certificate: harrysLaptopCertificate)
        let hermionesLaptop = try client(
            try user("hermione@example.com"),
            certificate: hermionesLaptopCertificate
        )
        try await store.store(harrysLaptop)
        try await store.store(hermionesLaptop)
        let harrysCredentials = try credentials(computedFrom: harrysLaptopCertificate)
        let hermionesCredentials = try credentials(computedFrom: hermionesLaptopCertificate)
        #expect(await store.client(ofType: MutualTLS.self, for: harrysCredentials) == harrysLaptop)
        #expect(await store.client(ofType: MutualTLS.self, for: hermionesCredentials) == hermionesLaptop)
    }

    @Test func `the same certificate resolves the same client on every lookup`() async throws {
        let store = ClientStore()
        let harrysLaptop = try client(try user("harry@example.com"), certificate: harrysLaptopCertificate)
        try await store.store(harrysLaptop)
        let credentials = try credentials(computedFrom: harrysLaptopCertificate)
        let first = await store.client(ofType: MutualTLS.self, for: credentials)
        let second = await store.client(ofType: MutualTLS.self, for: credentials)
        #expect(first == harrysLaptop)
        #expect(second == harrysLaptop)
    }

    @Test func `a certificate no client was stored under resolves to nil`() async throws {
        let store = ClientStore()
        try await store.store(try client(try user("harry@example.com"), certificate: harrysLaptopCertificate))
        let hermionesCredentials = try credentials(computedFrom: hermionesLaptopCertificate)
        #expect(await store.client(ofType: MutualTLS.self, for: hermionesCredentials) == nil)
    }

    @Test func `an empty store resolves to nil`() async throws {
        let store = ClientStore()
        let credentials = try credentials(computedFrom: harrysLaptopCertificate)
        #expect(await store.client(ofType: MutualTLS.self, for: credentials) == nil)
    }

    @Test func `the application caches a single store across accesses`() async throws {
        try await withRegistryApp { app in
            let harrysLaptop = try client(try user("harry@example.com"), certificate: harrysLaptopCertificate)
            try await app.clientStore.store(harrysLaptop)
            let credentials = try credentials(computedFrom: harrysLaptopCertificate)
            #expect(await app.clientStore.client(ofType: MutualTLS.self, for: credentials) == harrysLaptop)
        }
    }
}
