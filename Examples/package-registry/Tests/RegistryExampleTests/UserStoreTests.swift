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

    @Test func `round-trips a user by email`() async throws {
        let store = UserStore()
        let mona = User(email: try email("mona@example.com"))
        try await store.create(mona)
        #expect(await store.user(email: try email("mona@example.com")) == mona)
    }

    @Test func `distinct emails each resolve to their own user`() async throws {
        let store = UserStore()
        let mona = User(email: try email("mona@example.com"))
        let harry = User(email: try email("harry@example.com"))
        try await store.create(mona)
        try await store.create(harry)
        #expect(await store.user(email: try email("mona@example.com")) == mona)
        #expect(await store.user(email: try email("harry@example.com")) == harry)
    }

    @Test func `duplicate email throws emailAlreadyExists`() async throws {
        let store = UserStore()
        try await store.create(User(email: try email("mona@example.com")))
        await #expect(throws: UserStoreError.emailAlreadyExists) {
            try await store.create(User(email: try email("mona@example.com")))
        }
    }

    @Test func `an email differing only in casing and whitespace is a duplicate`() async throws {
        let store = UserStore()
        try await store.create(User(email: try email("Mona@Example.com")))
        await #expect(throws: UserStoreError.emailAlreadyExists) {
            try await store.create(User(email: try email("  mona@example.com ")))
        }
    }

    @Test func `unknown lookups return nil`() async throws {
        let store = UserStore()
        #expect(await store.user(email: try email("nobody@example.com")) == nil)
    }
}
