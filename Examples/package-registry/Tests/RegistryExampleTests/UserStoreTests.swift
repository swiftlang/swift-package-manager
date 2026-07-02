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

@Suite("UserStore")
struct UserStoreTests {
    private func email(_ raw: String) throws -> EmailAddress {
        try #require(EmailAddress(raw))
    }

    @Test func `round-trips a password user by email`() async throws {
        let store = UserStore()
        let mona = User(email: try email("mona@example.com"), credential: .password(hash: "bcrypt"))
        try await store.create(mona)
        #expect(await store.user(email: try email("mona@example.com")) == mona)
    }

    @Test func `round-trips a token user by token hash`() async throws {
        let store = UserStore()
        let mona = User(email: try email("mona@example.com"), credential: .token(hash: "abc123"))
        try await store.create(mona)
        #expect(await store.user(tokenHash: "abc123") == mona)
    }

    @Test func `duplicate email throws emailAlreadyExists`() async throws {
        let store = UserStore()
        try await store.create(User(email: try email("mona@example.com"), credential: .password(hash: "h1")))
        await #expect(throws: UserStoreError.emailAlreadyExists) {
            try await store.create(User(email: try email("mona@example.com"), credential: .password(hash: "h2")))
        }
    }

    @Test func `token collision throws and leaves no partial state`() async throws {
        let store = UserStore()
        try await store.create(User(email: try email("a@example.com"), credential: .token(hash: "shared")))
        await #expect(throws: UserStoreError.tokenAlreadyExists) {
            try await store.create(User(email: try email("b@example.com"), credential: .token(hash: "shared")))
        }
        #expect(await store.user(email: try email("b@example.com")) == nil)
        #expect(await store.user(tokenHash: "shared")?.email == (try email("a@example.com")))
    }

    @Test func `password users are absent from the token index`() async throws {
        let store = UserStore()
        try await store.create(User(email: try email("mona@example.com"), credential: .password(hash: "h")))
        #expect(await store.user(tokenHash: "h") == nil)
    }

    @Test func `unknown lookups return nil`() async throws {
        let store = UserStore()
        #expect(await store.user(email: try email("nobody@example.com")) == nil)
        #expect(await store.user(tokenHash: "missing") == nil)
    }
}
