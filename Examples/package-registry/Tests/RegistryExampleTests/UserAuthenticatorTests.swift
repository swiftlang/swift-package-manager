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
@testable import RegistryExample

@Suite("UserAuthenticator")
struct UserAuthenticatorTests {
    private func seededAuthenticator(
        _ seed: (UserRegistrar) async throws -> Void
    ) async throws -> UserAuthenticator {
        let store = UserStore()
        try await seed(UserRegistrar(store: store, tokenGenerator: TokenGenerator { "the-token" }))
        return UserAuthenticator(store: store)
    }

    // MARK: Basic

    @Test func `correct email and password authenticate`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        #expect(await auth.authenticate(email: "mona@example.com", password: "hunter2") != nil)
    }

    @Test func `basic login normalizes the email`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "Mona@Example.com", password: "hunter2")
        }
        let authenticated = await auth.authenticate(email: "  mona@example.com ", password: "hunter2")
        #expect(authenticated?.value == "mona@example.com")
    }

    @Test func `wrong password fails`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        #expect(await auth.authenticate(email: "mona@example.com", password: "wrong") == nil)
    }

    @Test func `unknown email fails`() async throws {
        let auth = try await seededAuthenticator { _ in }
        #expect(await auth.authenticate(email: "ghost@example.com", password: "hunter2") == nil)
    }

    @Test func `empty password fails`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        #expect(await auth.authenticate(email: "mona@example.com", password: "") == nil)
    }

    // MARK: Bearer

    @Test func `correct token authenticates`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: nil)
        }
        #expect(await auth.authenticate(token: "the-token") != nil)
    }

    @Test func `unknown token fails`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: nil)
        }
        #expect(await auth.authenticate(token: "some-other-token") == nil)
    }

    @Test func `empty token fails`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: nil)
        }
        #expect(await auth.authenticate(token: "") == nil)
    }

    // MARK: Cross-credential isolation

    @Test func `token user cannot authenticate via basic with the plaintext token`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: nil)
        }
        #expect(await auth.authenticate(email: "mona@example.com", password: "the-token") == nil)
    }

    @Test func `token user cannot authenticate via basic with the token hash`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: nil)
        }
        let hash = TokenHasher.hash("the-token")
        #expect(await auth.authenticate(email: "mona@example.com", password: hash) == nil)
    }

    @Test func `password user cannot authenticate via bearer`() async throws {
        let auth = try await seededAuthenticator {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        #expect(await auth.authenticate(token: "hunter2") == nil)
    }
}
