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

@Suite("Client management endpoints")
struct ClientRoutesTests {
    private struct MintedClient: Decodable {
        let id: String
        let token: String
    }

    private struct ListedClient: Decodable, Equatable {
        let id: String
        let method: String
    }

    private struct ClientList: Decodable {
        let clients: [ListedClient]
    }

    /// A password account created through the registration endpoint, so the
    /// credentials the tests present are the ones the application's own routes
    /// registered.
    private func register(
        _ tester: any TestingApplicationTester,
        email: String,
        password: String
    ) async throws {
        try await tester.test(
            .POST, "/users", body: jsonBody(#"{"email":"\#(email)","password":"\#(password)"}"#)
        ) { res async in
            #expect(res.status == .created)
        }
    }

    private func mintToken(
        _ tester: any TestingApplicationTester,
        headers: HTTPHeaders
    ) async throws -> MintedClient {
        var payload = ""
        try await tester.test(.POST, "/clients", headers: headers) { res async in
            #expect(res.status == .created)
            payload = res.body.string
        }
        return try JSONDecoder().decode(MintedClient.self, from: Data(payload.utf8))
    }

    private func listClients(
        _ tester: any TestingApplicationTester,
        headers: HTTPHeaders
    ) async throws -> [ListedClient] {
        var payload = ""
        try await tester.test(.GET, "/clients", headers: headers) { res async in
            #expect(res.status == .ok)
            payload = res.body.string
        }
        return try JSONDecoder().decode(ClientList.self, from: Data(payload.utf8)).clients
    }

    private func monasHeaders() -> HTTPHeaders {
        basicHeaders(email: "mona@example.com", password: "hunter2")
    }

    // MARK: POST /clients

    @Test func `minting returns 201 with a usable token`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let minted = try await mintToken(tester, headers: monasHeaders())

            #expect(!minted.id.isEmpty)
            #expect(!minted.token.isEmpty)
            try await tester.test(.POST, "/login", headers: bearerHeaders(minted.token)) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains(#""email":"mona@example.com""#))
            }
        }
    }

    @Test func `minting locates the new client`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")

            var location = ""
            var payload = ""
            try await tester.test(.POST, "/clients", headers: monasHeaders()) { res async in
                location = res.headers.first(name: .location) ?? ""
                payload = res.body.string
            }
            let minted = try JSONDecoder().decode(MintedClient.self, from: Data(payload.utf8))
            #expect(location.hasSuffix("/clients/\(minted.id)"))
        }
    }

    @Test func `minting leaves the credentials that asked for it working`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            _ = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(.POST, "/login", headers: monasHeaders()) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `a user can mint a token per machine, each logging in as that user`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())
            let desktop = try await mintToken(tester, headers: monasHeaders())

            #expect(laptop.token != desktop.token)
            #expect(laptop.id != desktop.id)
            for token in [laptop.token, desktop.token] {
                try await tester.test(.POST, "/login", headers: bearerHeaders(token)) { res async in
                    #expect(res.status == .ok)
                    #expect(res.body.string.contains(#""email":"mona@example.com""#))
                }
            }
        }
    }

    @Test func `a token can mint a further token for its own account`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())
            let fromLaptop = try await mintToken(tester, headers: bearerHeaders(laptop.token))

            #expect(fromLaptop.token != laptop.token)
            try await tester.test(.POST, "/login", headers: bearerHeaders(fromLaptop.token)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `minting without credentials is rejected with 401 problem+json`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")

            try await tester.test(.POST, "/clients") { res async in
                #expect(res.status == .unauthorized)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }

    @Test func `minting with invalid credentials is rejected with 401`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")

            try await tester.test(
                .POST, "/clients", headers: basicHeaders(email: "mona@example.com", password: "wrong")
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    // MARK: GET /clients

    @Test func `listing reports every client on the account and how it authenticates`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let password = try #require(try await listClients(tester, headers: monasHeaders()).first)
            #expect(password.method == "basic")
            let laptop = try await mintToken(tester, headers: monasHeaders())

            #expect(try await listClients(tester, headers: monasHeaders()) == [
                password,
                ListedClient(id: laptop.id, method: "bearer"),
            ])
        }
    }

    @Test func `a listed client reports its id and method, and nothing else`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            _ = try await mintToken(tester, headers: monasHeaders())

            var payload = ""
            try await tester.test(.GET, "/clients", headers: monasHeaders()) { res async in
                payload = res.body.string
            }
            let entries = try JSONDecoder()
                .decode([String: [[String: String]]].self, from: Data(payload.utf8))["clients"]
            #expect(try #require(entries).allSatisfy { Set($0.keys) == ["id", "method"] })
        }
    }

    @Test func `every client on an account sees the same listing`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())

            let viaPassword = try await listClients(tester, headers: monasHeaders())
            let viaToken = try await listClients(tester, headers: bearerHeaders(laptop.token))

            #expect(viaPassword.map(\.id) == viaToken.map(\.id))
            #expect(viaToken.map(\.id).contains(laptop.id))
        }
    }

    @Test func `listing shows a caller only their own clients`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            try await register(tester, email: "tim@example.com", password: "trustno1")
            let monasLaptop = try await mintToken(tester, headers: monasHeaders())

            let tims = try await listClients(
                tester, headers: basicHeaders(email: "tim@example.com", password: "trustno1")
            )
            #expect(tims.map(\.method) == ["basic"])
            #expect(!tims.map(\.id).contains(monasLaptop.id))
        }
    }

    @Test func `listing reveals no credential material`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(.GET, "/clients", headers: monasHeaders()) { res async in
                #expect(!res.body.string.contains(laptop.token))
                #expect(!res.body.string.contains(TokenHasher.hash(laptop.token).value))
                #expect(!res.body.string.contains("hunter2"))
                #expect(!res.body.string.contains("$2"))
            }
        }
    }

    @Test func `listing without credentials is rejected with 401`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")

            try await tester.test(.GET, "/clients") { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    // MARK: DELETE /clients/:id

    @Test func `revoking a client returns 204 and stops its token authenticating`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(.DELETE, "/clients/\(laptop.id)", headers: monasHeaders()) { res async in
                #expect(res.status == .noContent)
            }
            try await tester.test(.POST, "/login", headers: bearerHeaders(laptop.token)) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `a revoked client leaves the account's listing`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())
            let desktop = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(.DELETE, "/clients/\(laptop.id)", headers: monasHeaders()) { res async in
                #expect(res.status == .noContent)
            }

            let remaining = try await listClients(tester, headers: monasHeaders())
            #expect(!remaining.map(\.id).contains(laptop.id))
            #expect(remaining.map(\.id).contains(desktop.id))
        }
    }

    @Test func `revoking one token leaves the account's other tokens working`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())
            let desktop = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(.DELETE, "/clients/\(laptop.id)", headers: monasHeaders()) { res async in
                #expect(res.status == .noContent)
            }
            try await tester.test(.POST, "/login", headers: bearerHeaders(desktop.token)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `a client can revoke itself, after which its own credentials fail`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())
            let laptopHeaders = bearerHeaders(laptop.token)

            try await tester.test(.DELETE, "/clients/\(laptop.id)", headers: laptopHeaders) { res async in
                #expect(res.status == .noContent)
            }
            try await tester.test(.GET, "/clients", headers: laptopHeaders) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `revoking another user's client returns 404 and leaves it registered`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            try await register(tester, email: "tim@example.com", password: "trustno1")
            let monasLaptop = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(
                .DELETE,
                "/clients/\(monasLaptop.id)",
                headers: basicHeaders(email: "tim@example.com", password: "trustno1")
            ) { res async in
                #expect(res.status == .notFound)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
            try await tester.test(.POST, "/login", headers: bearerHeaders(monasLaptop.token)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `revoking an id no client holds returns 404`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")

            try await tester.test(.DELETE, "/clients/never-registered", headers: monasHeaders()) { res async in
                #expect(res.status == .notFound)
            }
        }
    }

    @Test func `revoking without credentials is rejected with 401`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(.DELETE, "/clients/\(laptop.id)") { res async in
                #expect(res.status == .unauthorized)
            }
            try await tester.test(.POST, "/login", headers: bearerHeaders(laptop.token)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    // MARK: An account keeps at least one client

    @Test func `revoking an account's only client is refused with 409 problem+json`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let onlyClient = try #require(try await listClients(tester, headers: monasHeaders()).first)

            try await tester.test(.DELETE, "/clients/\(onlyClient.id)", headers: monasHeaders()) { res async in
                #expect(res.status == .conflict)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
            try await tester.test(.POST, "/login", headers: monasHeaders()) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `a client can be replaced by minting its successor before revoking it`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let password = try #require(try await listClients(tester, headers: monasHeaders()).first)
            let replacement = try await mintToken(tester, headers: monasHeaders())

            try await tester.test(
                .DELETE, "/clients/\(password.id)", headers: bearerHeaders(replacement.token)
            ) { res async in
                #expect(res.status == .noContent)
            }

            try await tester.test(.POST, "/login", headers: monasHeaders()) { res async in
                #expect(res.status == .unauthorized)
            }
            #expect(try await listClients(tester, headers: bearerHeaders(replacement.token)).map(\.id) == [replacement.id])
        }
    }

    @Test func `a client revoked down to the last one cannot revoke itself`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await register(tester, email: "mona@example.com", password: "hunter2")
            let laptop = try await mintToken(tester, headers: monasHeaders())
            let laptopHeaders = bearerHeaders(laptop.token)
            let password = try #require(try await listClients(tester, headers: laptopHeaders).first)

            try await tester.test(.DELETE, "/clients/\(password.id)", headers: laptopHeaders) { res async in
                #expect(res.status == .noContent)
            }
            try await tester.test(.DELETE, "/clients/\(laptop.id)", headers: laptopHeaders) { res async in
                #expect(res.status == .conflict)
            }
            try await tester.test(.POST, "/login", headers: laptopHeaders) { res async in
                #expect(res.status == .ok)
            }
        }
    }
}
