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
@testable import RegistryExample

@Suite("ClientStore")
struct ClientStoreTests {
    private func user(_ raw: String) throws -> User {
        User(email: try #require(EmailAddress(raw)), credential: .password(hash: "bcrypt"))
    }

    private func client(_ user: User, _ value: String) -> Client {
        Client(user: user, id: Client.ID(rootCertificateAuthority: .none, value: value))
    }

    @Test func `round-trips a client by its ID`() async throws {
        let store = ClientStore()
        let certificateThumbprint1 = client(try user("harry@example.com"), "certificate thumbprint 1")
        try await store.create(certificateThumbprint1)
        #expect(await store.client(id: certificateThumbprint1.id) == certificateThumbprint1)
    }

    @Test func `returns every client belonging to a user`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let certificateThumbprint1 = client(harry, "certificate thumbprint 1")
        let certificateThumbprint2 = client(harry, "certificate thumbprint 2")
        try await store.create(certificateThumbprint1)
        try await store.create(certificateThumbprint2)
        #expect(await store.allClients(for: harry.email) == [certificateThumbprint1, certificateThumbprint2])
    }

    @Test func `scopes clients to their own user`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysCertificateThumbprint = client(harry, "certificate thumbprint 1")
        try await store.create(harrysCertificateThumbprint)
        try await store.create(client(hermione, "certificate thumbprint 2"))
        #expect(await store.allClients(for: harry.email) == [harrysCertificateThumbprint])
    }

    @Test func `duplicate ID throws clientAlreadyExists`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        try await store.create(client(harry, "certificate thumbprint 1"))
        await #expect(throws: ClientStoreError.clientAlreadyExists) {
            try await store.create(client(harry, "certificate thumbprint 1"))
        }
    }

    @Test func `duplicate ID leaves no partial state`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysCertificateThumbprint = client(harry, "certificate thumbprint 1")
        try await store.create(harrysCertificateThumbprint)
        await #expect(throws: ClientStoreError.clientAlreadyExists) {
            try await store.create(client(hermione, "certificate thumbprint 1"))
        }
        #expect(await store.allClients(for: hermione.email).isEmpty)
        #expect(await store.client(id: harrysCertificateThumbprint.id) == harrysCertificateThumbprint)
    }

    @Test func `unknown ID returns nil`() async throws {
        let store = ClientStore()
        let unknown = Client.ID(rootCertificateAuthority: .none, value: "missing")
        #expect(await store.client(id: unknown) == nil)
    }

    @Test func `user with no clients returns an empty array`() async throws {
        let store = ClientStore()
        #expect(await store.allClients(for: try user("voldemort@example.com").email).isEmpty)
    }

    @Test func `the application caches a single store across accesses`() async throws {
        try await withRegistryApp { app in
            let certificateThumbprint1 = client(try user("harry@example.com"), "certificate thumbprint 1")
            try await app.clientStore.create(certificateThumbprint1)
            #expect(await app.clientStore.client(id: certificateThumbprint1.id) == certificateThumbprint1)
        }
    }
}
