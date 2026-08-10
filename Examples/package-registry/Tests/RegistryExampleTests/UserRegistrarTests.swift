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
@testable import RegistryExample

@Suite("UserRegistrar")
struct UserRegistrarTests {
    /// A registrar and the two stores it writes to, so a test can assert on
    /// the user it created *and* the client that carries the credential.
    private struct Registry {
        let users: UserStore
        let clients: ClientStore
        let registrar: UserRegistrar

        init(mintingToken token: String = "minted-token") {
            let users = UserStore()
            let clients = ClientStore()
            self.users = users
            self.clients = clients
            self.registrar = UserRegistrar(
                store: users,
                clientRegistrar: ClientRegistrar(
                    store: clients,
                    tokenGenerator: TokenGenerator { token }
                )
            )
        }

        func register(email: String, password: String?) async throws -> RegistrationResult {
            try await registrar.register(email: email, password: password)
        }

        func basicClient(for email: EmailAddress) async -> RegisteredClient<BasicAuth>? {
            await clients.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: email))
        }

        func bearerClient(presenting token: String) async -> RegisteredClient<BearerAuth>? {
            await clients.client(
                ofType: BearerAuth.self,
                for: BearerAuth.Credentials(tokenHash: TokenHasher.hash(token))
            )
        }
    }

    @Test func `password registration returns no token and persists the user`() async throws {
        let registry = Registry()
        let result = try await registry.register(email: "mona@example.com", password: "hunter2")

        #expect(result.token == nil)
        #expect(result.user.email.value == "mona@example.com")
        #expect(await registry.users.user(email: result.user.email) == result.user)
    }

    @Test func `token registration returns the plaintext and stores only its hash`() async throws {
        let registry = Registry(mintingToken: "minted-token")
        let result = try await registry.register(email: "mona@example.com", password: nil)

        #expect(result.token == "minted-token")
        let client = try #require(await registry.bearerClient(presenting: "minted-token"))
        #expect(client.auth.credentials.tokenHash == TokenHasher.hash("minted-token"))
    }

    @Test func `empty password is rejected and mints no token`() async throws {
        let registry = Registry()
        await #expect(throws: RegistrationError.emptyPassword) {
            _ = try await registry.register(email: "mona@example.com", password: "")
        }
    }

    @Test func `invalid email is rejected`() async throws {
        let registry = Registry()
        await #expect(throws: RegistrationError.invalidEmail) {
            _ = try await registry.register(email: "not-an-email", password: "hunter2")
        }
    }

    @Test func `duplicate email throws the same error as an invalid one, across casing and whitespace`() async throws {
        let registry = Registry()
        _ = try await registry.register(email: "Mona@Example.com", password: "hunter2")
        await #expect(throws: RegistrationError.invalidEmail) {
            _ = try await registry.register(email: "  mona@example.com ", password: "other")
        }
    }

    @Test func `a registered token resolves to the user who registered it`() async throws {
        let registry = Registry(mintingToken: "round-trip-token")
        let result = try await registry.register(email: "mona@example.com", password: nil)

        let token = try #require(result.token)
        let client = try #require(await registry.bearerClient(presenting: token))
        #expect(client.user == result.user)
    }

    // MARK: The client created alongside the user

    @Test func `password registration also creates a Basic client under the user's email`() async throws {
        let registry = Registry()
        let result = try await registry.register(email: "mona@example.com", password: "hunter2")

        let client = try #require(await registry.basicClient(for: result.user.email))
        #expect(client.user == result.user)
        #expect(client.auth.passwordHash != "hunter2")
        #expect(try Bcrypt.verify("hunter2", created: client.auth.passwordHash))
    }

    @Test func `token registration creates a Bearer client and no Basic one`() async throws {
        let registry = Registry(mintingToken: "minted-token")
        let result = try await registry.register(email: "mona@example.com", password: nil)

        let client = try #require(await registry.bearerClient(presenting: "minted-token"))
        #expect(client.user == result.user)
        #expect(await registry.basicClient(for: result.user.email) == nil)
    }

    @Test func `a rejected registration creates no client`() async throws {
        let registry = Registry()
        await #expect(throws: RegistrationError.emptyPassword) {
            _ = try await registry.register(email: "mona@example.com", password: "")
        }

        let email = try #require(EmailAddress("mona@example.com"))
        #expect(await registry.basicClient(for: email) == nil)
    }

    @Test func `a rejected duplicate registration leaves the first user's client intact`() async throws {
        let registry = Registry()
        let first = try await registry.register(email: "mona@example.com", password: "hunter2")
        await #expect(throws: RegistrationError.invalidEmail) {
            _ = try await registry.register(email: "mona@example.com", password: "different")
        }

        let client = try #require(await registry.basicClient(for: first.user.email))
        #expect(client.user == first.user)
        #expect(try Bcrypt.verify("hunter2", created: client.auth.passwordHash))
    }
}
