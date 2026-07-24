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
}
