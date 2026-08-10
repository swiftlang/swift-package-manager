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
        User(email: try #require(EmailAddress(raw)))
    }

    private func client(_ user: User, token: String) -> RegisteredClient<BearerAuth> {
        RegisteredClient(user: user, auth: BearerAuth(token: token))
    }

    private func credentials(computedFrom token: String) -> BearerAuth.Credentials {
        BearerAuth.Credentials(tokenHash: TokenHasher.hash(token))
    }

    @Test func `round-trips a client stored under its token`() async throws {
        let store = ClientStore()
        let harrysLaptop = client(try user("harry@example.com"), token: "harrys-laptop-token")
        try await store.store(harrysLaptop)
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token"))
                == harrysLaptop
        )
    }

    @Test func `a client stored from a plaintext token resolves by its hash credentials`() async throws {
        let store = ClientStore()
        let harrysLaptop = client(try user("harry@example.com"), token: "harrys-laptop-token")
        try await store.store(harrysLaptop)
        let credentials = BearerAuth(tokenHash: TokenHasher.hash("harrys-laptop-token")).credentials
        #expect(await store.client(ofType: BearerAuth.self, for: credentials) == harrysLaptop)
    }

    @Test func `resolves each token to its own user's client`() async throws {
        let store = ClientStore()
        let harrysLaptop = client(try user("harry@example.com"), token: "harrys-laptop-token")
        let hermionesLaptop = client(try user("hermione@example.com"), token: "hermiones-laptop-token")
        try await store.store(harrysLaptop)
        try await store.store(hermionesLaptop)
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token"))
                == harrysLaptop
        )
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "hermiones-laptop-token"))
                == hermionesLaptop
        )
    }

    @Test func `the same token resolves the same client on every lookup`() async throws {
        let store = ClientStore()
        let harrysLaptop = client(try user("harry@example.com"), token: "harrys-laptop-token")
        try await store.store(harrysLaptop)
        let credentials = credentials(computedFrom: "harrys-laptop-token")
        let first = await store.client(ofType: BearerAuth.self, for: credentials)
        let second = await store.client(ofType: BearerAuth.self, for: credentials)
        #expect(first == harrysLaptop)
        #expect(second == harrysLaptop)
    }

    @Test func `a token no client was stored under resolves to nil`() async throws {
        let store = ClientStore()
        try await store.store(client(try user("harry@example.com"), token: "harrys-laptop-token"))
        let hermionesCredentials = credentials(computedFrom: "hermiones-laptop-token")
        #expect(await store.client(ofType: BearerAuth.self, for: hermionesCredentials) == nil)
    }

    @Test func `an empty store resolves to nil`() async throws {
        let store = ClientStore()
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token")) == nil
        )
    }

    @Test func `a client of one method is not resolvable as another`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        try await store.store(client(harry, token: "harrys-laptop-token"))
        #expect(
            await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email)) == nil
        )
    }

    @Test func `the application caches a single store across accesses`() async throws {
        try await withRegistryApp { app in
            let harrysLaptop = client(try user("harry@example.com"), token: "harrys-laptop-token")
            try await app.clientStore.store(harrysLaptop)
            let credentials = credentials(computedFrom: "harrys-laptop-token")
            #expect(await app.clientStore.client(ofType: BearerAuth.self, for: credentials) == harrysLaptop)
        }
    }
}
