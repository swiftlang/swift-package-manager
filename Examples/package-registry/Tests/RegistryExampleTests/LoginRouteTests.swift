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
import VaporTesting
@testable import RegistryExample

@Suite("POST /login endpoint")
struct LoginRouteTests {
    private func seedPasswordUser(_ app: Application, email: String, password: String) async throws {
        _ = try await UserRegistrar(store: app.userStore).register(email: email, password: password)
    }

    // MARK: Status-only cases

    /// The account state seeded into the store before a login attempt.
    enum Seed: Sendable {
        case none
        case passwordUser(email: String, password: String)
        case tokenUser(email: String, token: String)

        func apply(to app: Application) async throws {
            switch self {
            case .none:
                break
            case let .passwordUser(email, password):
                _ = try await UserRegistrar(store: app.userStore).register(email: email, password: password)
            case let .tokenUser(email, token):
                _ = try await UserRegistrar(store: app.userStore, tokenGenerator: TokenGenerator { token })
                    .register(email: email, password: nil)
            }
        }
    }

    /// One login scenario: seed some state, present an `Authorization` header
    /// (or none), and expect a status. `name` becomes the case's identifier in
    /// test output via ``CustomTestStringConvertible``, preserving what were
    /// once individual test-function names.
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let seed: Seed
        let authorization: String?
        let expectedStatus: HTTPResponseStatus
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "valid basic credentials return 200",
             seed: .passwordUser(email: "mona@example.com", password: "hunter2"),
             authorization: basic("mona@example.com", "hunter2"), expectedStatus: .ok),
        Case(name: "basic login matches the registered email case-insensitively",
             seed: .passwordUser(email: "Mona@Example.com", password: "hunter2"),
             authorization: basic("mona@example.com", "hunter2"), expectedStatus: .ok),
        Case(name: "lowercase basic scheme is accepted",
             seed: .passwordUser(email: "mona@example.com", password: "hunter2"),
             authorization: "basic \(base64Encode("mona@example.com:hunter2"))", expectedStatus: .ok),
        Case(name: "malformed base64 basic credential returns 401 not 501",
             seed: .none, authorization: "Basic !!!not-base64!!!", expectedStatus: .unauthorized),
        Case(name: "basic credential without a colon returns 401",
             seed: .none, authorization: "Basic \(base64Encode("emailonly"))", expectedStatus: .unauthorized),
        Case(name: "empty basic password returns 401",
             seed: .passwordUser(email: "mona@example.com", password: "hunter2"),
             authorization: basic("mona@example.com", ""), expectedStatus: .unauthorized),
        Case(name: "token user cannot log in via basic using the plaintext token",
             seed: .tokenUser(email: "mona@example.com", token: "the-token"),
             authorization: basic("mona@example.com", "the-token"), expectedStatus: .unauthorized),
        Case(name: "valid bearer token returns 200",
             seed: .tokenUser(email: "mona@example.com", token: "the-token"),
             authorization: "Bearer the-token", expectedStatus: .ok),
        Case(name: "unknown bearer token returns 401",
             seed: .tokenUser(email: "mona@example.com", token: "the-token"),
             authorization: "Bearer wrong-token", expectedStatus: .unauthorized),
        Case(name: "empty bearer token returns 401",
             seed: .none, authorization: "Bearer ", expectedStatus: .unauthorized),
        Case(name: "a garbage scheme token returns 501",
             seed: .none, authorization: "Foo bar", expectedStatus: .notImplemented),
    ]

    private static func basic(_ email: String, _ password: String) -> String {
        "Basic \(base64Encode("\(email):\(password)"))"
    }

    @Test(arguments: cases)
    func `login reports the expected status`(_ loginCase: Case) async throws {
        try await withRegistryApp { app in
            try await loginCase.seed.apply(to: app)
            let headers = loginCase.authorization.map(authorizationHeaders) ?? HTTPHeaders()
            try await app.testing().test(.POST, "/login", headers: headers) { res async in
                #expect(res.status == loginCase.expectedStatus)
            }
        }
    }

    // MARK: Cases with response-shape assertions beyond the status

    @Test func `wrong password returns 401 problem+json with WWW-Authenticate`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await app.testing().test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "wrong")
            ) { res async in
                #expect(res.status == .unauthorized)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.headers.first(name: .wwwAuthenticate) == "Basic, Bearer")
            }
        }
    }

    @Test func `unknown email and wrong password return identical 401 bodies`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let tester = try app.testing()
            var unknownBody = ""
            var wrongBody = ""
            try await tester.test(
                .POST, "/login", headers: basicHeaders(email: "ghost@example.com", password: "hunter2")
            ) { res async in
                #expect(res.status == .unauthorized)
                unknownBody = res.body.string
            }
            try await tester.test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "wrong")
            ) { res async in
                #expect(res.status == .unauthorized)
                wrongBody = res.body.string
            }
            #expect(unknownBody == wrongBody)
        }
    }

    @Test func `missing Authorization header returns 401`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.POST, "/login") { res async in
                #expect(res.status == .unauthorized)
                #expect(res.headers.first(name: .wwwAuthenticate) == "Basic, Bearer")
            }
        }
    }

    @Test func `an unsupported scheme returns 501 problem+json`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/login", headers: authorizationHeaders("Digest username=\"mona\"")
            ) { res async in
                #expect(res.status == .notImplemented)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }
}
