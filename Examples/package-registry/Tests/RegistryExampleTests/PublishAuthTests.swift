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
        _ = try await UserRegistrar(store: app.userStore).register(email: email, password: password)
    }

    private func publishBody() throws -> ByteBuffer {
        publishMultipartBody(zip: try makeHelloWorldZip(), metadata: nil)
    }

    @Test func `with auth disabled, publishing needs no login`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }

    @Test func `with auth enabled, publishing without a login is 401`() async throws {
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

    @Test func `with auth enabled, publishing after a login succeeds`() async throws {
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
                #expect(res.status == .created)
            }
        }
    }

    @Test func `with auth enabled, a failed login does not unlock publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let tester = try app.testing()

            try await tester.test(
                .POST, "/login", headers: basicHeaders(email: "mona@example.com", password: "wrong")
            ) { res async in
                #expect(res.status == .unauthorized)
            }

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func `with auth enabled, a token login also unlocks publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            let token = "the-token"
            _ = try await UserRegistrar(store: app.userStore, tokenGenerator: TokenGenerator { token })
                .register(email: "mona@example.com", password: nil)
            let tester = try app.testing()

            try await tester.test(.POST, "/login", headers: bearerHeaders(token)) { res async in
                #expect(res.status == .ok)
            }

            try await tester.test(
                .PUT, "/catalogdev/HelloWorld/1.0.0", headers: publishHeaders(), body: try publishBody()
            ) { res async in
                #expect(res.status == .created)
            }
        }
    }
}
