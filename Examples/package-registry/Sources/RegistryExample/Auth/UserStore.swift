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
}

/// An in-memory, actor-isolated store of registered ``User`` accounts.
///
/// Users are keyed by their normalized ``EmailAddress``, which is the whole
/// of an account's identity. Credentials are not stored here: they belong to
/// the ``RegisteredClient``s a user registers, so resolving a presented
/// password or token is the ``ClientStore``'s job.
///
/// Actor isolation serializes reads and writes; ``create(_:)`` is a single
/// synchronous, suspension-free step that checks for a duplicate before
/// inserting, so concurrent registrations of the same email cannot both
/// succeed. All state is ephemeral.
public actor UserStore {
    private var usersByEmail: [EmailAddress: User] = [:]

    /// Creates an empty user store.
    public init() {}

    /// Inserts a new user.
    ///
    /// - Parameter user: The ``User`` to persist.
    /// - Throws: ``UserStoreError/emailAlreadyExists`` if the email is taken.
    public func create(_ user: User) throws {
        guard usersByEmail[user.email] == nil else {
            throw UserStoreError.emailAlreadyExists
        }
        usersByEmail[user.email] = user
    }

    /// Returns the user registered under `email`, or `nil` if none.
    public func user(email: EmailAddress) -> User? {
        usersByEmail[email]
    }
}
