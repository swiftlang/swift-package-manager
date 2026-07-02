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

    private func seedTokenUser(_ app: Application, email: String, token: String) async throws {
        _ = try await UserRegistrar(store: app.userStore, tokenGenerator: TokenGenerator { token })
            .register(email: email, password: nil)
    }

    // MARK: Basic

    @Test func `valid basic credentials return 200`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await app.testing().test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "Content-Version") == "1")
            }
        }
    }

    @Test func `basic login matches the registered email case-insensitively`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "Mona@Example.com", password: "hunter2")
            try await app.testing().test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            ) { res async in
                #expect(res.status == .ok)
            }
        }
    }

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

    @Test func `lowercase basic scheme is accepted`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let raw = "basic \(base64Encode("mona@example.com:hunter2"))"
            try await app.testing().test(.POST, "/login", headers: authorizationHeaders(raw)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `malformed base64 basic credential returns 401 not 501`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/login", headers: authorizationHeaders("Basic !!!not-base64!!!")
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `basic credential without a colon returns 401`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/login", headers: authorizationHeaders("Basic \(base64Encode("emailonly"))")
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `empty basic password returns 401`() async throws {
        try await withRegistryApp { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await app.testing().test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "")
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `token user cannot log in via basic using the plaintext token`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            try await app.testing().test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "the-token")
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    // MARK: Bearer

    @Test func `valid bearer token returns 200`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            try await app.testing().test(.POST, "/login", headers: bearerHeaders("the-token")) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `unknown bearer token returns 401`() async throws {
        try await withRegistryApp { app in
            try await seedTokenUser(app, email: "mona@example.com", token: "the-token")
            try await app.testing().test(.POST, "/login", headers: bearerHeaders("wrong-token")) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `empty bearer token returns 401`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.POST, "/login", headers: authorizationHeaders("Bearer ")) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    // MARK: Scheme handling

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

    @Test func `a garbage scheme token returns 501`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/login", headers: authorizationHeaders("Foo bar")
            ) { res async in
                #expect(res.status == .notImplemented)
            }
        }
    }
}
