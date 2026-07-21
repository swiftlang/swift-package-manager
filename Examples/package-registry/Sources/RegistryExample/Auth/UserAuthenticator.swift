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
/// enumerate registered emails. The account lookup itself is a hash-indexed
/// dictionary access in ``UserStore`` — not a linear scan that could
/// terminate early on a match — so it contributes no email-dependent timing
/// of its own; the only credential-dependent work is the bcrypt step, which
/// the decoy forces to run on every attempt. bcrypt runs on the shared
/// thread pool so it never blocks the event loop.
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
    /// - Returns: The authenticated user's normalized ``EmailAddress`` if a
    ///   password user with `rawEmail` exists and `password` verifies against
    ///   its bcrypt hash; otherwise `nil`.
    public func authenticate(email rawEmail: String, password: String) async -> EmailAddress? {
        guard !password.isEmpty else { return nil }
        guard let email = EmailAddress(rawEmail) else { return nil }
        let user = await store.user(email: email)
        let storedHash = Self.passwordHash(of: user)
        let verified = await Self.verify(password, against: storedHash ?? Self.decoyHash)
        return (storedHash != nil && verified) ? email : nil
    }

    /// Verifies a Bearer token.
    ///
    /// - Parameter token: The presented bearer token.
    /// - Returns: The token user's normalized ``EmailAddress`` if a token user
    ///   whose token hashes to the presented value exists; otherwise `nil`.
    public func authenticate(token: String) async -> EmailAddress? {
        guard !token.isEmpty else { return nil }
        let user = await store.user(tokenHash: TokenHasher.hash(token))
        guard case .token = user?.credential else { return nil }
        return user?.email
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

    /// A precomputed, valid bcrypt hash used as the constant-time decoy for
    /// unknown (or token-only) accounts on the Basic path.
    ///
    /// Hardcoding a known-good hash — rather than computing one at launch with
    /// a `try?` that could fall back to an empty string — guarantees the Basic
    /// path always runs a full bcrypt verification. An empty or malformed
    /// decoy would let `Bcrypt.verify` short-circuit cheaply for a missing
    /// account, reopening the timing side-channel this decoy exists to close.
    /// The plaintext behind the hash is irrelevant and unrecoverable; its
    /// random salt means no real password can ever verify against it.
    static let decoyHash = "$2y$12$VR4mlQAwtp/g2T1HgvFYDOCUbNVVZ07E5VavY/sIAHo4hs4Ukr/9m"
}
