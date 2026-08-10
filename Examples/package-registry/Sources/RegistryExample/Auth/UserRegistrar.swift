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
    let clientRegistrar: ClientRegistrar

    /// Creates a registrar backed by `store`.
    ///
    /// - Parameters:
    ///   - store: The user store to insert into.
    ///   - clientRegistrar: Registers the client that carries the new
    ///     account's credential.
    public init(store: UserStore, clientRegistrar: ClientRegistrar) {
        self.store = store
        self.clientRegistrar = clientRegistrar
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
    ///   empty password; ``ClientStoreError/clientAlreadyExists`` on a token
    ///   collision.
    public func register(email rawEmail: String, password: String?) async throws -> RegistrationResult {
        guard let email = EmailAddress(rawEmail) else {
            throw RegistrationError.invalidEmail
        }

        let user = User(email: email)
        do {
            try await store.create(user)
        } catch UserStoreError.emailAlreadyExists {
            throw RegistrationError.invalidEmail
        }

        guard let password else {
            let client = try await clientRegistrar.registerBearerClient(for: user)
            return RegistrationResult(user: user, token: client.token)
        }

        guard !password.isEmpty else {
            throw RegistrationError.emptyPassword
        }
        _ = try await clientRegistrar.registerBasicClient(for: user, password: password)

        return RegistrationResult(user: user, token: nil)
    }
}
