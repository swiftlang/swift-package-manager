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

/// Errors thrown by ``IdentityStore/create(_:)``.
public enum IdentityStoreError: Error, Equatable, Sendable {
    /// An identity with the same ``Identity/ID`` — the same root CA paired
    /// with the same value — is already registered, possibly to a different
    /// user. Two users may never share one identity.
    case identityAlreadyExists
}

/// An in-memory, actor-isolated store of the ``Identity`` records that make
/// authenticated requests on behalf of a ``User``.
///
/// Two indices are maintained: identities keyed by their ``Identity/ID``
/// (for resolving the identity presented on a request) and a mapping from a
/// user's ``EmailAddress`` to the IDs they own, in the order they were
/// created (for listing everything a user authenticates with).
///
/// Actor isolation serializes reads and writes; ``create(_:)`` is a single
/// synchronous, suspension-free step that validates the ID index before
/// mutating either, so a duplicate can never leave a half-registered
/// identity behind and concurrent creations of the same ID cannot both
/// succeed. All state is ephemeral.
public actor IdentityStore {
    private var identitiesByID: [Identity.ID: Identity] = [:]
    private var identityIDsByUserEmail: [EmailAddress: [Identity.ID]] = [:]

    /// Creates an empty identity store.
    public init() {}

    /// Inserts a new identity, indexing it under its owner's email.
    ///
    /// - Parameter identity: The ``Identity`` to persist.
    /// - Throws: ``IdentityStoreError/identityAlreadyExists`` if the ID is
    ///   already registered.
    public func create(_ identity: Identity) throws {
        guard identitiesByID[identity.id] == nil else {
            throw IdentityStoreError.identityAlreadyExists
        }
        identitiesByID[identity.id] = identity
        identityIDsByUserEmail[identity.user.email, default: []].append(identity.id)
    }

    /// Returns the identity registered under `id`, or `nil` if none.
    public func identity(id: Identity.ID) -> Identity? {
        identitiesByID[id]
    }

    /// Returns every identity owned by the user with `userEmail`, in
    /// creation order, or an empty array if the user owns none.
    public func allIdentities(for userEmail: EmailAddress) -> [Identity] {
        identityIDsByUserEmail[userEmail, default: []].compactMap { identitiesByID[$0] }
    }
}
