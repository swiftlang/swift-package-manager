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

/// Records every ``PasswordVerifier`` invocation, capturing the hash each was
/// asked to verify against. This lets a test assert the Basic path performs
/// identical credential-independent work — exactly one bcrypt verification,
/// against the decoy for a missing account — whether or not the account
/// exists. Asserting *operation count* rather than wall-clock keeps the
/// constant-time guard deterministic and free of timing flakiness, while a
/// deleted decoy is still caught: it drops the unknown-account count to zero.
actor VerifyRecorder {
    private(set) var hashes: [String] = []
    private let result: Bool

    init(result: Bool = false) {
        self.result = result
    }

    func record(against hash: String) -> Bool {
        hashes.append(hash)
        return result
    }
}

@Suite("Constant-time Basic authentication")
struct ConstantTimeAuthTests {
    private func authenticator(
        recording recorder: VerifyRecorder,
        seed: (UserRegistrar) async throws -> Void
    ) async throws -> UserAuthenticator {
        let store = UserStore()
        try await seed(UserRegistrar(store: store))
        let verifier = PasswordVerifier { _, hash in await recorder.record(against: hash) }
        return UserAuthenticator(store: store, passwordVerifier: verifier)
    }

    @Test func `an unknown email still runs one verification, against the decoy`() async throws {
        let recorder = VerifyRecorder()
        let auth = try await authenticator(recording: recorder) { _ in }
        _ = await auth.authenticate(email: "ghost@example.com", password: "hunter2")
        #expect(await recorder.hashes == [UserAuthenticator.decoyHash])
    }

    @Test func `a wrong password runs one verification, against the stored hash`() async throws {
        let recorder = VerifyRecorder()
        let auth = try await authenticator(recording: recorder) {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        _ = await auth.authenticate(email: "mona@example.com", password: "wrong")
        let hashes = await recorder.hashes
        #expect(hashes.count == 1)
        #expect(hashes.first != UserAuthenticator.decoyHash)
    }

    @Test func `known and unknown emails perform the same number of verifications`() async throws {
        let known = VerifyRecorder()
        let knownAuth = try await authenticator(recording: known) {
            _ = try await $0.register(email: "mona@example.com", password: "hunter2")
        }
        _ = await knownAuth.authenticate(email: "mona@example.com", password: "wrong")

        let unknown = VerifyRecorder()
        let unknownAuth = try await authenticator(recording: unknown) { _ in }
        _ = await unknownAuth.authenticate(email: "ghost@example.com", password: "wrong")

        let knownCount = await known.hashes.count
        let unknownCount = await unknown.hashes.count
        #expect(knownCount == unknownCount)
    }

    @Test func `the decoy's cost factor matches a freshly hashed password`() throws {
        let fresh = try Bcrypt.hash("a password")
        #expect(bcryptCost(UserAuthenticator.decoyHash) != nil)
        #expect(bcryptCost(UserAuthenticator.decoyHash) == bcryptCost(fresh))
    }
}

private func bcryptCost(_ hash: String) -> Int? {
    let fields = hash.split(separator: "$", omittingEmptySubsequences: true)
    guard fields.count >= 2 else { return nil }
    return Int(fields[1])
}
