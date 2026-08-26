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

@Suite("Registration and login end-to-end")
struct AuthEndToEndTests {
    private struct RegisteredUser: Decodable {
        let email: String
        let token: String?
    }

    private func register(
        _ tester: any TestingApplicationTester,
        body: String
    ) async throws -> RegisteredUser {
        var payload = ""
        try await tester.test(.POST, "/users", body: jsonBody(body)) { res async in
            #expect(res.status == .created)
            payload = res.body.string
        }
        return try JSONDecoder().decode(RegisteredUser.self, from: Data(payload.utf8))
    }

    @Test func `a password user can register and then log in`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            let registered = try await register(tester, body: #"{"email":"mona@example.com","password":"hunter2"}"#)
            #expect(registered.token == nil)

            try await tester.test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `a token user can register and then log in with the minted token`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            let registered = try await register(tester, body: #"{"email":"mona@example.com"}"#)
            let token = try #require(registered.token)

            try await tester.test(.POST, "/login", headers: bearerHeaders(token)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `one user's token does not authenticate as another`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            let mona = try await register(tester, body: #"{"email":"mona@example.com"}"#)
            let tim = try await register(tester, body: #"{"email":"tim@example.com"}"#)
            let monaToken = try #require(mona.token)
            let timToken = try #require(tim.token)

            var monaBody = ""
            try await tester.test(.POST, "/login", headers: bearerHeaders(monaToken)) { res async in
                #expect(res.status == .ok)
                monaBody = res.body.string
            }
            #expect(try JSONDecoder().decode(RegisteredUser.self, from: Data(monaBody.utf8)).email == "mona@example.com")

            var timBody = ""
            try await tester.test(.POST, "/login", headers: bearerHeaders(timToken)) { res async in
                #expect(res.status == .ok)
                timBody = res.body.string
            }
            #expect(try JSONDecoder().decode(RegisteredUser.self, from: Data(timBody.utf8)).email == "tim@example.com")

            try await tester.test(.POST, "/login", headers: bearerHeaders("\(monaToken)-tampered")) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `two clients of one user log in as that same user`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            let registered = try await register(tester, body: #"{"email":"mona@example.com","password":"hunter2"}"#)
            let mona = User(email: try #require(EmailAddress(registered.email)))
            _ = try await ClientRegistrar(
                store: app.clientStore,
                tokenGenerator: TokenGenerator { "monas-ci-token" }
            ).registerBearerClient(for: mona)

            for headers in [
                basicHeaders(email: "mona@example.com", password: "hunter2"),
                bearerHeaders("monas-ci-token"),
            ] {
                try await tester.test(.POST, "/login", headers: headers) { res async in
                    #expect(res.status == .ok)
                    let body = res.body.string
                    let loggedIn = try? JSONDecoder().decode(RegisteredUser.self, from: Data(body.utf8))
                    #expect(loggedIn?.email == "mona@example.com")
                }
            }
        }
    }

    private struct MintedClient: Decodable {
        let id: String
        let token: String
    }

    private struct ClientList: Decodable {
        struct Client: Decodable, Equatable {
            let id: String
            let method: String
        }

        let clients: [Client]
    }

    private func mint(_ tester: any TestingApplicationTester, headers: HTTPHeaders) async throws -> MintedClient {
        var payload = ""
        try await tester.test(.POST, "/clients", headers: headers) { res async in
            #expect(res.status == .created)
            payload = res.body.string
        }
        return try JSONDecoder().decode(MintedClient.self, from: Data(payload.utf8))
    }

    private func list(_ tester: any TestingApplicationTester, headers: HTTPHeaders) async throws -> ClientList {
        var payload = ""
        try await tester.test(.GET, "/clients", headers: headers) { res async in
            #expect(res.status == .ok)
            payload = res.body.string
        }
        return try JSONDecoder().decode(ClientList.self, from: Data(payload.utf8))
    }

    @Test func `a user adds a token per machine, then retires one of them`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            _ = try await register(tester, body: #"{"email":"mona@example.com","password":"hunter2"}"#)
            let password = basicHeaders(email: "mona@example.com", password: "hunter2")
            let passwordClient = try #require(try await list(tester, headers: password).clients.first)
            #expect(passwordClient.method == "basic")

            let laptop = try await mint(tester, headers: password)
            let ci = try await mint(tester, headers: password)

            for token in [laptop.token, ci.token] {
                try await tester.test(.POST, "/login", headers: bearerHeaders(token)) { res async in
                    #expect(res.status == .ok)
                }
            }

            #expect(try await list(tester, headers: bearerHeaders(ci.token)).clients == [
                passwordClient,
                ClientList.Client(id: laptop.id, method: "bearer"),
                ClientList.Client(id: ci.id, method: "bearer"),
            ])

            try await tester.test(.DELETE, "/clients/\(laptop.id)", headers: bearerHeaders(ci.token)) { res async in
                #expect(res.status == .noContent)
            }

            try await tester.test(.POST, "/login", headers: bearerHeaders(laptop.token)) { res async in
                #expect(res.status == .unauthorized)
            }
            try await tester.test(.POST, "/login", headers: bearerHeaders(ci.token)) { res async in
                #expect(res.status == .ok)
            }
            #expect(try await list(tester, headers: password).clients == [
                passwordClient,
                ClientList.Client(id: ci.id, method: "bearer"),
            ])
        }
    }
}
