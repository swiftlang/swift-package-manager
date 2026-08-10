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

/// Verifies presented credentials against the ``ClientStore``.
///
/// Two verification paths mirror the two credential shapes, and each is
/// strictly typed to its own authentication method: a password is only ever
/// checked against a ``BasicAuth`` client's bcrypt hash and a token only
/// against a ``BearerAuth`` client's token hash. There is no path by which a
/// Bearer client authenticates via Basic, or a password is compared to a
/// stored token hash.
///
/// What a verified credential establishes is *which client* is calling, so
/// each path returns that client's credentials rather than an account. The
/// user behind the client — and, in time, the client's permissions — is
/// ``ClientResolver``'s to answer, from the store, at the moment a handler
/// asks.
///
/// The Basic path is written to run in constant time with respect to
/// account existence: an email holding no Basic client is verified
/// against a fixed decoy hash so a bcrypt computation is always performed,
/// closing the timing side-channel that would otherwise let an attacker
/// enumerate registered emails. The client lookup itself is a hash-indexed
/// dictionary access in ``ClientStore`` — not a linear scan that could
/// terminate early on a match — so it contributes no email-dependent timing
/// of its own; the only credential-dependent work is the bcrypt step, which
/// the decoy forces to run on every attempt. bcrypt runs on the shared
/// thread pool so it never blocks the event loop.
public struct ClientAuthenticator: Sendable {
    let clientStore: ClientStore
    let passwordVerifier: PasswordVerifier

    /// Creates an authenticator backed by `store`.
    ///
    /// - Parameters:
    ///   - clientStore: Map of all clients in the registry
    ///   - passwordVerifier: The Basic-path verification seam. Defaults to
    ///     bcrypt; tests inject a recording double.
    public init(clientStore: ClientStore, passwordVerifier: PasswordVerifier = .bcrypt) {
        self.clientStore = clientStore
        self.passwordVerifier = passwordVerifier
    }

    /// Verifies an HTTP Basic credential.
    ///
    /// - Parameters:
    ///   - rawEmail: The username component (an email address).
    ///   - password: The password component.
    /// - Returns: The ``BasicAuth/Credentials`` identifying the calling client
    ///   if a Basic client with `rawEmail` exists and `password` verifies
    ///   against its bcrypt hash; otherwise `nil`.
    public func authenticate(email rawEmail: String, password: String) async -> BasicAuth.Credentials? {
        guard !password.isEmpty else { return nil }
        guard let email = EmailAddress(rawEmail) else { return nil }
        let client = await clientStore.client(
            ofType: BasicAuth.self,
            for: BasicAuth.Credentials(email: email)
        )
        let storedHash = client?.auth.passwordHash
        let verified = await passwordVerifier.verify(password, against: storedHash ?? Self.decoyHash)
        return verified ? client?.auth.credentials : nil
    }

    /// Verifies a Bearer token.
    ///
    /// - Parameter token: The presented bearer token.
    /// - Returns: The ``BearerAuth/Credentials`` identifying the calling client
    ///   if a Bearer client whose token hashes to the presented value exists;
    ///   otherwise `nil`.
    public func authenticate(token: String) async -> BearerAuth.Credentials? {
        guard !token.isEmpty, token.count <= Self.maxTokenLength else { return nil }
        let client = await clientStore.client(
            ofType: BearerAuth.self,
            for: BearerAuth.Credentials(tokenHash: TokenHasher.hash(token))
        )
        return client?.auth.credentials
    }

    /// The longest presented bearer token this registry will even hash.
    ///
    /// A minted token is 43 base64url characters; this generous ceiling
    /// leaves room for alternate token formats while bounding the work an
    /// attacker can force with an enormous string — SHA-256 cost is linear in
    /// input length, so an uncapped token lets a single request (or a flood of
    /// them) burn CPU hashing megabytes that could never match a real token.
    static let maxTokenLength = 256

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
