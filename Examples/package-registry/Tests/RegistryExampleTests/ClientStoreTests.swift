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

    private func client(_ user: User, token: String, id: ClientID? = nil) -> RegisteredClient<BearerAuth> {
        RegisteredClient(id: id ?? ClientID("\(token)-id"), user: user, auth: BearerAuth(token: token))
    }

    private func client(_ user: User, password: String) -> RegisteredClient<BasicAuth> {
        RegisteredClient(
            id: ClientID("\(user.email.value)-password-id"),
            user: user,
            auth: BasicAuth(email: user.email, passwordHash: password)
        )
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

    @Test func `a client is not stored under an id another client already holds`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let sharedID = ClientID("shared-id")
        try await store.store(client(harry, token: "harrys-laptop-token", id: sharedID))

        await #expect(throws: ClientStoreError.idAlreadyExists) {
            try await store.store(client(harry, token: "harrys-desktop-token", id: sharedID))
        }
        #expect(await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-desktop-token")) == nil)
    }

    // MARK: Listing a user's clients

    @Test func `lists every client registered to a user, in registration order`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        let desktop = client(harry, token: "harrys-desktop-token")
        try await store.store(laptop)
        try await store.store(desktop)

        #expect(await store.clients(for: harry) == [laptop.summary, desktop.summary])
    }

    @Test func `lists a user's clients whatever method they authenticate with`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        try await store.store(client(harry, password: "hashed-hunter2"))
        try await store.store(client(harry, token: "harrys-laptop-token"))

        #expect(await store.clients(for: harry).map(\.method) == ["basic", "bearer"])
    }

    @Test func `lists only the clients of the user asked about`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        try await store.store(client(harry, token: "harrys-laptop-token"))
        let hermionesLaptop = client(hermione, token: "hermiones-laptop-token")
        try await store.store(hermionesLaptop)

        #expect(await store.clients(for: hermione) == [hermionesLaptop.summary])
    }

    @Test func `lists nothing for a user holding no clients`() async throws {
        let store = ClientStore()
        try await store.store(client(try user("harry@example.com"), token: "harrys-laptop-token"))
        #expect(await store.clients(for: try user("hermione@example.com")).isEmpty)
    }

    // MARK: Revocation

    @Test func `a revoked client's credentials resolve to nothing`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        try await store.store(laptop)
        try await store.store(client(harry, token: "harrys-desktop-token"))
        try await store.revoke(laptop.id, of: harry)

        #expect(await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token")) == nil)
    }

    @Test func `a revoked client leaves its user's listing`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        let desktop = client(harry, token: "harrys-desktop-token")
        try await store.store(laptop)
        try await store.store(desktop)
        try await store.revoke(laptop.id, of: harry)

        #expect(await store.clients(for: harry) == [desktop.summary])
    }

    @Test func `revoking returns the removed client's summary`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        try await store.store(laptop)
        try await store.store(client(harry, token: "harrys-desktop-token"))

        #expect(try await store.revoke(laptop.id, of: harry) == laptop.summary)
    }

    @Test func `a revoked client's siblings keep authenticating`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        let desktop = client(harry, token: "harrys-desktop-token")
        let password = client(harry, password: "hashed-hunter2")
        try await store.store(laptop)
        try await store.store(desktop)
        try await store.store(password)
        try await store.revoke(laptop.id, of: harry)

        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-desktop-token"))
                == desktop
        )
        #expect(await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email)) == password)
    }

    @Test func `revoking an id no client is registered under removes nothing`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        let desktop = client(harry, token: "harrys-desktop-token")
        try await store.store(laptop)
        try await store.store(desktop)

        await #expect(throws: ClientStoreError.noSuchClient) {
            try await store.revoke(ClientID("never-registered"), of: harry)
        }
        #expect(await store.clients(for: harry) == [laptop.summary, desktop.summary])
    }

    @Test func `one user cannot revoke another user's client`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysLaptop = client(harry, token: "harrys-laptop-token")
        try await store.store(harrysLaptop)
        try await store.store(client(harry, token: "harrys-desktop-token"))
        try await store.store(client(hermione, token: "hermiones-laptop-token"))

        await #expect(throws: ClientStoreError.noSuchClient) {
            try await store.revoke(harrysLaptop.id, of: hermione)
        }
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token"))
                == harrysLaptop
        )
    }

    @Test func `a revoked client's credentials are free to be registered again`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        try await store.store(laptop)
        try await store.store(client(harry, token: "harrys-desktop-token"))
        try await store.revoke(laptop.id, of: harry)

        let reissued = client(harry, token: "harrys-laptop-token", id: ClientID("reissued-id"))
        try await store.store(reissued)
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token"))
                == reissued
        )
    }

    // MARK: An account keeps at least one client

    @Test func `a user's only client cannot be revoked`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        try await store.store(laptop)

        await #expect(throws: ClientStoreError.lastRemainingClient) {
            try await store.revoke(laptop.id, of: harry)
        }
        #expect(await store.clients(for: harry) == [laptop.summary])
        #expect(
            await store.client(ofType: BearerAuth.self, for: credentials(computedFrom: "harrys-laptop-token"))
                == laptop
        )
    }

    @Test func `a user can be revoked down to one client, but no further`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let laptop = client(harry, token: "harrys-laptop-token")
        let desktop = client(harry, token: "harrys-desktop-token")
        try await store.store(laptop)
        try await store.store(desktop)

        try await store.revoke(laptop.id, of: harry)
        await #expect(throws: ClientStoreError.lastRemainingClient) {
            try await store.revoke(desktop.id, of: harry)
        }
        #expect(await store.clients(for: harry) == [desktop.summary])
    }

    @Test func `an id belonging to someone else is unknown, whatever the caller holds`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysLaptop = client(harry, token: "harrys-laptop-token")
        try await store.store(harrysLaptop)
        try await store.store(client(harry, token: "harrys-desktop-token"))
        try await store.store(client(hermione, token: "hermiones-only-token"))

        await #expect(throws: ClientStoreError.noSuchClient) {
            try await store.revoke(harrysLaptop.id, of: hermione)
        }
    }

    @Test func `the last client of one user does not block another user's revocation`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysLaptop = client(harry, token: "harrys-laptop-token")
        try await store.store(harrysLaptop)
        try await store.store(client(harry, token: "harrys-desktop-token"))
        try await store.store(client(hermione, token: "hermiones-only-token"))

        #expect(try await store.revoke(harrysLaptop.id, of: harry) == harrysLaptop.summary)
        #expect(await store.clients(for: hermione).count == 1)
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
