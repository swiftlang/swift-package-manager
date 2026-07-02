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

import Vapor

/// Verifies credentials presented at login against the ``UserStore``.
///
/// Two verification paths mirror the two credential shapes, and each is
/// strictly typed to its own credential case: a password is only ever
/// checked against a ``User/Credential/password(hash:)`` and a token only
/// against a ``User/Credential/token(hash:)``. There is no path by which a
/// token user authenticates via Basic, or a password is compared to a
/// stored token hash.
///
/// The Basic path is written to run in constant time with respect to
/// account existence: an unknown email (or a token-only user) is verified
/// against a fixed decoy hash so a bcrypt computation is always performed,
/// closing the timing side-channel that would otherwise let an attacker
/// enumerate registered emails. bcrypt runs on the shared thread pool so
/// it never blocks the event loop.
public struct UserAuthenticator: Sendable {
    let store: UserStore

    /// Creates an authenticator backed by `store`.
    ///
    /// - Parameter store: The user store to verify against.
    public init(store: UserStore) {
        self.store = store
    }

    /// Verifies an HTTP Basic credential.
    ///
    /// - Parameters:
    ///   - rawEmail: The username component (an email address).
    ///   - password: The password component.
    /// - Returns: `true` only if a password user with `rawEmail` exists and
    ///   `password` verifies against its bcrypt hash.
    public func authenticate(email rawEmail: String, password: String) async -> Bool {
        guard !password.isEmpty else { return false }
        let user = await EmailAddress(rawEmail).asyncFlatMap { await store.user(email: $0) }
        let storedHash = Self.passwordHash(of: user)
        let verified = await Self.verify(password, against: storedHash ?? Self.decoyHash)
        return storedHash != nil && verified
    }

    /// Verifies a Bearer token.
    ///
    /// - Parameter token: The presented bearer token.
    /// - Returns: `true` only if a token user whose token hashes to the
    ///   presented value exists.
    public func authenticate(token: String) async -> Bool {
        guard !token.isEmpty else { return false }
        let user = await store.user(tokenHash: TokenHasher.hash(token))
        guard case .token = user?.credential else { return false }
        return true
    }

    private static func passwordHash(of user: User?) -> String? {
        guard case let .password(hash) = user?.credential else { return nil }
        return hash
    }

    private static func verify(_ password: String, against hash: String) async -> Bool {
        let result = try? await NIOThreadPool.singleton.runIfActive {
            try Bcrypt.verify(password, created: hash)
        }
        return result ?? false
    }

    private static let decoyHash: String =
        (try? Bcrypt.hash("decoy value for constant-time credential verification")) ?? ""
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
