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

/// Errors thrown by ``UserStore/create(_:)``.
public enum UserStoreError: Error, Equatable, Sendable {
    /// A user with the same normalized ``EmailAddress`` already exists.
    /// Surfaced to registration clients as a `409 Conflict`.
    case emailAlreadyExists
    /// A token user whose token hashes to an already-registered value was
    /// submitted. With 256-bit tokens this is astronomically unlikely and
    /// is treated as a server-side condition rather than a client error.
    case tokenAlreadyExists
}

/// An in-memory, actor-isolated store of registered ``User`` accounts.
///
/// Two indices are maintained: users keyed by their normalized
/// ``EmailAddress`` (for HTTP Basic login and duplicate detection) and a
/// mapping from a token's hash to its owner's email (for Bearer login).
/// Only token users appear in the second index, so a password user can
/// never be resolved from a bearer token.
///
/// Actor isolation serializes reads and writes; ``create(_:)`` is a single
/// synchronous, suspension-free step that validates both indices before
/// mutating either, so a duplicate can never leave a half-registered user
/// behind and concurrent registrations of the same email cannot both
/// succeed. All state is ephemeral.
public actor UserStore {
    private var usersByEmail: [EmailAddress: User] = [:]
    private var emailByTokenHash: [String: EmailAddress] = [:]

    /// Creates an empty user store.
    public init() {}

    /// Inserts a new user, indexing token users by their token hash.
    ///
    /// - Parameter user: The fully hashed ``User`` to persist.
    /// - Throws: ``UserStoreError/emailAlreadyExists`` if the email is
    ///   taken, or ``UserStoreError/tokenAlreadyExists`` if a token user's
    ///   hash collides with an existing entry.
    public func create(_ user: User) throws {
        guard usersByEmail[user.email] == nil else {
            throw UserStoreError.emailAlreadyExists
        }
        if case let .token(hash) = user.credential {
            guard emailByTokenHash[hash] == nil else {
                throw UserStoreError.tokenAlreadyExists
            }
            emailByTokenHash[hash] = user.email
        }
        usersByEmail[user.email] = user
    }

    /// Returns the user registered under `email`, or `nil` if none.
    public func user(email: EmailAddress) -> User? {
        usersByEmail[email]
    }

    /// Returns the token user whose token hashes to `tokenHash`, or `nil`
    /// if no token user matches.
    public func user(tokenHash: String) -> User? {
        guard let email = emailByTokenHash[tokenHash] else { return nil }
        return usersByEmail[email]
    }
}
