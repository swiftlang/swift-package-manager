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
import Vapor
import VaporTesting
@testable import RegistryExample

@Suite("Publish endpoint authentication gate")
struct PublishAuthTests {
    private func seedPasswordUser(_ app: Application, email: String, password: String) async throws {
        _ = try await userRegistrar(for: app).register(email: email, password: password)
    }

    private func seedTokenUser(_ app: Application, email: String, token: String) async throws {
        _ = try await userRegistrar(for: app, tokenGenerator: TokenGenerator { token })
            .register(email: email, password: nil)
    }

    private func publishBody() throws -> ByteBuffer {
        publishMultipartBody(zip: try makeHelloWorldZip(), metadata: nil)
    }

    private func authorizedPublishHeaders(_ authorization: String) -> HTTPHeaders {
        var headers = publishHeaders()
        headers.replaceOrAdd(name: .authorization, value: authorization)
        return headers
    }

    private func basicPublishHeaders(email: String, password: String) -> HTTPHeaders {
        authorizedPublishHeaders("Basic \(base64Encode("\(email):\(password)"))")
    }

    private func bearerPublishHeaders(_ token: String) -> HTTPHeaders {
        authorizedPublishHeaders("Bearer \(token)")
    }

    @Test func `with auth disabled, publishing needs no credentials`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    @Test func `configure requires auth by default`() async throws {
        let app = try await Application.make(.testing)
        app.logger.logLevel = .warning
        do {
            try await configure(app)
            try await app.asyncBoot()
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test func `with auth enabled, publishing with no credentials is 401`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.headers.first(name: .wwwAuthenticate) == "Basic, Bearer")
            }
        }
    }

    @Test func `with auth enabled, valid basic credentials authorize publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: basicPublishHeaders(email: "mona@example.com", password: "hunter2"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    @Test func `with auth enabled, a valid token authorizes publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: bearerPublishHeaders("the-token"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    @Test func `with auth enabled, either of a user's clients authorizes publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            let registration = try await userRegistrar(for: app)
                .register(email: "mona@example.com", password: "hunter2")
            _ = try await ClientRegistrar(
                store: app.clientStore,
                tokenGenerator: TokenGenerator { "the-token" }
            ).registerBearerClient(for: registration.user)
            let tester = try app.testing()

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: basicPublishHeaders(email: "mona@example.com", password: "hunter2"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/2.0.0",
                headers: bearerPublishHeaders("the-token"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    private struct MintedClient: Decodable {
        let id: String
        let token: String
    }

    @Test func `with auth enabled, a token minted through the clients endpoint authorizes publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            _ = try await userRegistrar(for: app).register(email: "mona@example.com", password: "hunter2")
            let tester = try app.testing()

            var payload = ""
            try await tester.test(
                .POST, "/clients", headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ) { res async in
                #expect(res.status == .created)
                payload = res.body.string
            }
            let minted = try JSONDecoder().decode(MintedClient.self, from: Data(payload.utf8))

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: bearerPublishHeaders(minted.token),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    @Test func `with auth enabled, a revoked client no longer authorizes publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            let registration = try await userRegistrar(for: app)
                .register(email: "mona@example.com", password: "hunter2")
            let ciClient = try await ClientRegistrar(
                store: app.clientStore,
                tokenGenerator: TokenGenerator { "the-token" }
            ).registerBearerClient(for: registration.user)
            let tester = try app.testing()

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: bearerPublishHeaders("the-token"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }

            try await app.clientStore.revoke(ciClient.client.id, of: registration.user)

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/2.0.0",
                headers: bearerPublishHeaders("the-token"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
            }

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/2.0.0",
                headers: basicPublishHeaders(email: "mona@example.com", password: "hunter2"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    @Test func `with auth enabled, invalid credentials are rejected with 401`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: basicPublishHeaders(email: "mona@example.com", password: "wrong"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `with auth enabled, credentials are re-checked on every request`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let tester = try app.testing()

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: basicPublishHeaders(email: "mona@example.com", password: "hunter2"),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/2.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `with auth enabled, a prior login does not authorize a credential-less publish`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let tester = try app.testing()

            try await tester.test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ) { res async in
                #expect(res.status == .ok)
            }

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `with auth enabled, an unsupported auth scheme is 501`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0",
                headers: authorizedPublishHeaders("Digest username=\"mona\""),
                body: try publishBody()
            ) { res async in
                #expect(res.status == .notImplemented)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }
}
