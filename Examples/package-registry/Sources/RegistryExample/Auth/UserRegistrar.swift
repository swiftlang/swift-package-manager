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

/// Errors thrown by ``UserRegistrar/register(email:password:)``.
public enum RegistrationError: Error, Equatable, Sendable {
    /// Surfaced as `400 Bad Request`
    case invalidEmail
    /// A `password` field was present but empty. Also surfaced as
    /// `400 Bad Request` — distinct from an absent password, which mints a
    /// token user.
    /// The distinction between the two cases is for internal logging only
    case emptyPassword
}

/// The outcome of a successful registration.
///
/// ``token`` is non-`nil` only for token users, carrying the freshly
/// minted plaintext token that the client must persist — it is returned
/// exactly once and never recoverable afterward, since the store keeps
/// only its hash.
public struct RegistrationResult: Sendable, Equatable {
    /// The newly created account.
    public let user: User
    /// The one-time plaintext token, present only for token users.
    public let token: String?
}

/// Creates new users from unauthenticated registration requests.
///
/// The registrar owns all credential preparation — email validation,
/// bcrypt password hashing, and token generation/hashing — so that
/// ``UserStore/create(_:)`` stays a synchronous, atomic insert. Password
/// hashing is offloaded to the shared thread pool so bcrypt's CPU cost
/// never blocks the event loop serving other requests.
public struct UserRegistrar: Sendable {
    let store: UserStore
    let tokenGenerator: TokenGenerator

    /// Creates a registrar backed by `store`.
    ///
    /// - Parameters:
    ///   - store: The user store to insert into.
    ///   - tokenGenerator: The source of minted tokens. Defaults to the
    ///     system CSPRNG; tests inject a deterministic generator.
    public init(store: UserStore, tokenGenerator: TokenGenerator = .secureRandom) {
        self.store = store
        self.tokenGenerator = tokenGenerator
    }

    /// Registers a new user.
    ///
    /// A non-`nil`, non-empty `password` creates a Basic-auth user; a `nil`
    /// password mints a token user. An empty-string password is rejected.
    ///
    /// - Parameters:
    ///   - rawEmail: The email exactly as supplied by the client.
    ///   - password: The chosen password, or `nil` to mint a token.
    /// - Returns: The created user, plus the one-time token for token
    ///   users.
    /// - Throws: ``RegistrationError/invalidEmail`` for an invalid or
    ///   already-registered email, ``RegistrationError/emptyPassword`` for an
    ///   empty password; ``UserStoreError/tokenAlreadyExists`` on a token
    ///   collision.
    public func register(email rawEmail: String, password: String?) async throws -> RegistrationResult {
        guard let email = EmailAddress(rawEmail) else {
            throw RegistrationError.invalidEmail
        }
        let prepared = try await makeCredential(password: password)
        let user = User(email: email, credential: prepared.credential)
        do {
            try await store.create(user)
        } catch UserStoreError.emailAlreadyExists {
            throw RegistrationError.invalidEmail
        }
        return RegistrationResult(user: user, token: prepared.token)
    }

    private func makeCredential(
        password: String?
    ) async throws -> (credential: User.Credential, token: String?) {
        guard let password else {
            let token = tokenGenerator.makeToken()
            return (.token(hash: TokenHasher.hash(token)), token)
        }
        guard !password.isEmpty else {
            throw RegistrationError.emptyPassword
        }
        let hash = try await Self.hashPassword(password)
        return (.password(hash: hash), nil)
    }

    private static func hashPassword(_ password: String) async throws -> String {
        try await NIOThreadPool.singleton.runIfActive {
            try Bcrypt.hash(password)
        }
    }
}
