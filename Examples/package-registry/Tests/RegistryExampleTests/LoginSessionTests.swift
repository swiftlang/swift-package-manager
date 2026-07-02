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

@Suite("LoginSession")
struct LoginSessionTests {
    private func email(_ raw: String) throws -> EmailAddress {
        try #require(EmailAddress(raw))
    }

    @Test func `a fresh session has no active user`() async throws {
        let session = LoginSession()
        #expect(await session.hasActiveUser == false)
    }

    @Test func `logging a user in makes a user active`() async throws {
        let session = LoginSession()
        await session.logIn(try email("mona@example.com"))
        #expect(await session.hasActiveUser)
    }

    @Test func `a logged-in user is reported as logged in`() async throws {
        let session = LoginSession()
        let mona = try email("mona@example.com")
        await session.logIn(mona)
        #expect(await session.isLoggedIn(mona))
    }

    @Test func `a user who never logged in is not reported as logged in`() async throws {
        let session = LoginSession()
        await session.logIn(try email("mona@example.com"))
        #expect(await session.isLoggedIn(try email("tim@example.com")) == false)
    }

    @Test func `logging the same user in twice is idempotent`() async throws {
        let session = LoginSession()
        let mona = try email("mona@example.com")
        await session.logIn(mona)
        await session.logIn(mona)
        #expect(await session.isLoggedIn(mona))
    }
}
