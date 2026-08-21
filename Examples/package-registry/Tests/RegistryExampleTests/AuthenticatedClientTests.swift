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

@Suite("AuthenticatedClient")
struct AuthenticatedClientTests {
    private func seedPasswordUser(_ app: Application, email: String, password: String) async throws {
        _ = try await userRegistrar(for: app).register(email: email, password: password)
    }

    private func seedTokenUser(_ app: Application, email: String, token: String) async throws {
        _ = try await userRegistrar(for: app, tokenGenerator: TokenGenerator { token })
            .register(email: email, password: nil)
    }

    // MARK: Which client authenticated

    @Test func `valid basic credentials authenticate a basic client`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            )
            #expect(request.auth.has(AuthenticatedClient<BasicAuth>.self))
        }
    }

    @Test func `a valid token authenticates a bearer client`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))
            #expect(request.auth.has(AuthenticatedClient<BearerAuth>.self))
        }
    }

    @Test func `invalid credentials authenticate no client`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "wrong")
            )
            #expect(!request.auth.has(AuthenticatedClient<BasicAuth>.self))
            #expect(!request.auth.has(AuthenticatedClient<BearerAuth>.self))
        }
    }

    // MARK: One slot per authentication method

    @Test func `a basic client does not satisfy a bearer client requirement`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            )
            #expect(!request.auth.has(AuthenticatedClient<BearerAuth>.self))
        }
    }

    @Test func `a bearer client does not satisfy a basic client requirement`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))
            #expect(!request.auth.has(AuthenticatedClient<BasicAuth>.self))
        }
    }

    // MARK: The credentials carried

    @Test func `a basic client carries the normalized email that verified`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "Mona@Example.com", password: "hunter2")
            let request = try await authenticatedRequest(
                for: app, headers: basicHeaders(email: "Mona@Example.com", password: "hunter2")
            )
            let client = try #require(request.auth.get(AuthenticatedClient<BasicAuth>.self))
            #expect(client.credentials.email.value == "mona@example.com")
        }
    }

    @Test func `a bearer client carries the hash of the token that verified`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))
            let client = try #require(request.auth.get(AuthenticatedClient<BearerAuth>.self))
            #expect(client.credentials.tokenHash == TokenHasher.hash("the-token"))
        }
    }

    @Test func `a bearer client does not carry the plaintext token`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            let request = try await authenticatedRequest(for: app, headers: bearerHeaders("the-token"))
            let client = try #require(request.auth.get(AuthenticatedClient<BearerAuth>.self))
            #expect(client.credentials.tokenHash.value != "the-token")
        }
    }
}
