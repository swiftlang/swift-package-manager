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

@Suite("UserRegistrar")
struct UserRegistrarTests {
    @Test func `password registration stores a verifiable bcrypt hash and no token`() async throws {
        let registrar = UserRegistrar(store: UserStore())
        let result = try await registrar.register(email: "mona@example.com", password: "hunter2")

        #expect(result.token == nil)
        #expect(result.user.email.value == "mona@example.com")
        guard case let .password(hash) = result.user.credential else {
            Issue.record("expected a password credential")
            return
        }
        #expect(hash != "hunter2")
        #expect(try Bcrypt.verify("hunter2", created: hash))
    }

    @Test func `token registration returns the plaintext and stores only its hash`() async throws {
        let registrar = UserRegistrar(store: UserStore(), tokenGenerator: TokenGenerator { "minted-token" })
        let result = try await registrar.register(email: "mona@example.com", password: nil)

        #expect(result.token == "minted-token")
        #expect(result.user.credential == .token(hash: TokenHasher.hash("minted-token")))
    }

    @Test func `empty password is rejected and mints no token`() async throws {
        let registrar = UserRegistrar(store: UserStore())
        await #expect(throws: RegistrationError.emptyPassword) {
            _ = try await registrar.register(email: "mona@example.com", password: "")
        }
    }

    @Test func `invalid email is rejected`() async throws {
        let registrar = UserRegistrar(store: UserStore())
        await #expect(throws: RegistrationError.invalidEmail) {
            _ = try await registrar.register(email: "not-an-email", password: "hunter2")
        }
    }

    @Test func `duplicate email throws the same error as an invalid one, across casing and whitespace`() async throws {
        let registrar = UserRegistrar(store: UserStore())
        _ = try await registrar.register(email: "Mona@Example.com", password: "hunter2")
        await #expect(throws: RegistrationError.invalidEmail) {
            _ = try await registrar.register(email: "  mona@example.com ", password: "other")
        }
    }

    @Test func `a registered token authenticates and is stored hashed`() async throws {
        let store = UserStore()
        let registrar = UserRegistrar(store: store, tokenGenerator: TokenGenerator { "round-trip-token" })
        let result = try await registrar.register(email: "mona@example.com", password: nil)

        let token = try #require(result.token)
        #expect(await store.user(tokenHash: TokenHasher.hash(token))?.email.value == "mona@example.com")
    }
}
