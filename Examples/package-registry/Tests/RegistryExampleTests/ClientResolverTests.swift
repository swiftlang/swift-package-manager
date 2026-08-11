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

@Suite("ClientResolver")
struct ClientResolverTests {
    /// A user holding two clients: the Basic one created with the account, and
    /// a Bearer one registered afterwards for the same account.
    private func seedUserWithTwoClients(
        _ app: Application,
        email: String,
        password: String,
        token: String
    ) async throws -> User {
        let registration = try await userRegistrar(for: app).register(email: email, password: password)
        _ = try await ClientRegistrar(
            store: app.clientStore,
            tokenGenerator: TokenGenerator { token }
        ).registerBearerClient(for: registration.user)
        return registration.user
    }

    @Test func `resolves the user behind a basic-authenticated request`() async throws {
        try await withRegistryApp { app in
            let registration = try await userRegistrar(for: app)
                .register(email: "mona@example.com", password: "hunter2")
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            )
            let resolved = await ClientResolver(store: app.clientStore).user(authenticating: request)
            #expect(resolved == registration.user)
        }
    }

    @Test func `resolves the user behind a bearer-authenticated request`() async throws {
        try await withRegistryApp { app in
            let registration = try await userRegistrar(for: app, tokenGenerator: TokenGenerator { "the-token" })
                .register(email: "mona@example.com", password: nil)
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))
            let resolved = await ClientResolver(store: app.clientStore).user(authenticating: request)
            #expect(resolved == registration.user)
        }
    }

    @Test func `resolves no user for a request that authenticated nothing`() async throws {
        try await withRegistryApp { app in
            _ = try await userRegistrar(for: app).register(email: "mona@example.com", password: "hunter2")
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "wrong")
            )
            #expect(await ClientResolver(store: app.clientStore).user(authenticating: request) == nil)
        }
    }

    @Test func `resolves no user for a request carrying no credentials`() async throws {
        try await withRegistryApp { app in
            let request = try await authenticatedRequest(for: app, headers: HTTPHeaders())
            #expect(await ClientResolver(store: app.clientStore).user(authenticating: request) == nil)
        }
    }

    // MARK: Many clients, one user

    @Test func `both of a user's clients resolve to that one user`() async throws {
        try await withRegistryApp { app in
            let mona = try await seedUserWithTwoClients(
                app, email: "mona@example.com", password: "hunter2", token: "the-token"
            )
            let resolver = ClientResolver(store: app.clientStore)

            let viaBasic = await resolver.user(authenticating: try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ))
            let viaBearer = await resolver.user(authenticating: try await authenticatedRequest(
                for: app, headers: bearerHeaders("the-token")
            ))

            #expect(viaBasic == mona)
            #expect(viaBearer == mona)
        }
    }

    @Test func `each user's clients resolve only to their own account`() async throws {
        try await withRegistryApp { app in
            _ = try await seedUserWithTwoClients(
                app, email: "mona@example.com", password: "hunter2", token: "monas-token"
            )
            let tim = try await seedUserWithTwoClients(
                app, email: "tim@example.com", password: "trustno1", token: "tims-token"
            )
            let resolver = ClientResolver(store: app.clientStore)

            let viaTimsToken = await resolver.user(authenticating: try await authenticatedRequest(
                for: app, headers: bearerHeaders("tims-token")
            ))
            let viaTimsPassword = await resolver.user(authenticating: try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "tim@example.com", password: "trustno1")
            ))

            #expect(viaTimsToken == tim)
            #expect(viaTimsPassword == tim)
        }
    }

    // MARK: Which client is calling

    @Test func `describes the bearer client behind a request`() async throws {
        try await withRegistryApp { app in
            let registration = try await userRegistrar(for: app, tokenGenerator: TokenGenerator { "the-token" })
                .register(email: "mona@example.com", password: nil)
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))

            let summary = await ClientResolver(store: app.clientStore).client(authenticating: request)
            let registered = try #require(await app.clientStore.clients(for: registration.user).first)
            #expect(summary == registered)
            #expect(summary?.method == "bearer")
        }
    }

    @Test func `describes the basic client behind a request`() async throws {
        try await withRegistryApp { app in
            let mona = try await seedUserWithTwoClients(
                app, email: "mona@example.com", password: "hunter2", token: "the-token"
            )
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            )

            let summary = await ClientResolver(store: app.clientStore).client(authenticating: request)
            #expect(summary?.method == "basic")
            #expect(summary?.user == mona)
        }
    }

    @Test func `each of a user's clients describes itself, not its sibling`() async throws {
        try await withRegistryApp { app in
            let mona = try await seedUserWithTwoClients(
                app, email: "mona@example.com", password: "hunter2", token: "the-token"
            )
            let resolver = ClientResolver(store: app.clientStore)

            let viaBasic = await resolver.client(authenticating: try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ))
            let viaBearer = await resolver.client(authenticating: try await authenticatedRequest(
                for: app, headers: bearerHeaders("the-token")
            ))

            #expect(viaBasic?.id != viaBearer?.id)
            #expect(await app.clientStore.clients(for: mona).map(\.id) == [viaBasic?.id, viaBearer?.id].compactMap { $0 })
        }
    }

    @Test func `describes no client for a request that authenticated nothing`() async throws {
        try await withRegistryApp { app in
            let request = try await authenticatedRequest(for: app, headers: HTTPHeaders())
            #expect(await ClientResolver(store: app.clientStore).client(authenticating: request) == nil)
        }
    }

    @Test func `a revoked client stops resolving on requests it already authenticated`() async throws {
        try await withRegistryApp { app in
            let mona = try await seedUserWithTwoClients(
                app, email: "mona@example.com", password: "hunter2", token: "the-token"
            )
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))
            let resolver = ClientResolver(store: app.clientStore)
            let summary = try #require(await resolver.client(authenticating: request))

            try await app.clientStore.revoke(summary.id, of: mona)

            #expect(await resolver.client(authenticating: request) == nil)
            #expect(await resolver.user(authenticating: request) == nil)
        }
    }
}
