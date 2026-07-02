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

@Suite("POST /users registration endpoint")
struct UserRouteTests {
    @Test func `password registration returns 201 with the email and no token`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/users", body: jsonBody(#"{"email":"mona@example.com","password":"hunter2"}"#)
            ) { res async in
                #expect(res.status == .created)
                #expect(res.headers.first(name: .contentType) == "application/json")
                #expect(res.headers.first(name: "Content-Version") == "1")
                #expect(res.body.string.contains(#""email":"mona@example.com""#))
                #expect(!res.body.string.contains("token"))
            }
        }
    }

    private struct DecodedUser: Decodable {
        let email: String
        let token: String?
    }

    @Test func `token registration returns 201 including a token`() async throws {
        try await withRegistryApp { app in
            var body = ""
            try await app.testing().test(
                .POST, "/users", body: jsonBody(#"{"email":"mona@example.com"}"#)
            ) { res async in
                #expect(res.status == .created)
                body = res.body.string
            }
            let decoded = try JSONDecoder().decode(DecodedUser.self, from: Data(body.utf8))
            #expect(decoded.email == "mona@example.com")
            #expect(try #require(decoded.token).isEmpty == false)
        }
    }

    @Test func `a null password mints a token user`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/users", body: jsonBody(#"{"email":"mona@example.com","password":null}"#)
            ) { res async in
                #expect(res.status == .created)
                #expect(res.body.string.contains(#""token":"#))
            }
        }
    }

    @Test func `empty password is rejected with 400 problem+json`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/users", body: jsonBody(#"{"email":"mona@example.com","password":""}"#)
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.body.string.contains("password must not be empty"))
            }
        }
    }

    @Test func `invalid email is rejected with 400`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/users", body: jsonBody(#"{"email":"not-an-email","password":"hunter2"}"#)
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.body.string.contains("invalid email"))
            }
        }
    }

    @Test func `malformed JSON is a deliberate 400 not a 500`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/users", body: jsonBody(#"{"email": "#)
            ) { res async in
                #expect(res.status == .badRequest)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }

    @Test func `an empty body is a 400 not a 500`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.POST, "/users", body: ByteBuffer()) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func `duplicate email is rejected with 409`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await tester.test(
                .POST, "/users", body: jsonBody(#"{"email":"mona@example.com","password":"hunter2"}"#)
            ) { res async in
                #expect(res.status == .created)
            }
            try await tester.test(
                .POST, "/users", body: jsonBody(#"{"email":"mona@example.com","password":"other"}"#)
            ) { res async in
                #expect(res.status == .conflict)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
            }
        }
    }

    @Test func `duplicate detection is case and whitespace insensitive`() async throws {
        try await withRegistryApp { app in
            let tester = try app.testing()
            try await tester.test(
                .POST, "/users", body: jsonBody(#"{"email":"Mona@Example.com","password":"hunter2"}"#)
            ) { res async in
                #expect(res.status == .created)
            }
            try await tester.test(
                .POST, "/users", body: jsonBody(#"{"email":"  mona@example.com ","password":"other"}"#)
            ) { res async in
                #expect(res.status == .conflict)
            }
        }
    }

    @Test func `registration is not blocked by the registry v1 Accept header`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .POST, "/users", headers: acceptJSON,
                body: jsonBody(#"{"email":"mona@example.com","password":"hunter2"}"#)
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }
}
