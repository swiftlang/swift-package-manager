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

/// Errors thrown by ``ClientStore/create(_:)``.
public enum ClientStoreError: Error, Equatable, Sendable {
    /// A client with the same ``Client/ID`` — the same root CA paired
    /// with the same value — is already registered, possibly to a different
    /// user. Two users may never share one client.
    case clientAlreadyExists
}

/// An in-memory, actor-isolated store of the ``Client`` records that make
/// authenticated requests on behalf of a ``User``.
///
/// Two indices are maintained: clients keyed by their ``Client/ID``
/// (for resolving the client presented on a request) and a mapping from a
/// user's ``EmailAddress`` to the IDs they own, in the order they were
/// created (for listing everything a user authenticates with).
///
/// Actor isolation serializes reads and writes; ``create(_:)`` is a single
/// synchronous, suspension-free step that validates the ID index before
/// mutating either, so a duplicate can never leave a half-registered
/// client behind and concurrent creations of the same ID cannot both
/// succeed. All state is ephemeral.
public actor ClientStore {
    private var clientsByID: [Client.ID: Client] = [:]
    private var clientIDsByUserEmail: [EmailAddress: [Client.ID]] = [:]

    /// Creates an empty client store.
    public init() {}

    /// Inserts a new client, indexing it under its owner's email.
    ///
    /// - Parameter client: The ``Client`` to persist.
    /// - Throws: ``ClientStoreError/clientAlreadyExists`` if the ID is
    ///   already registered.
    public func create(_ client: Client) throws {
        guard clientsByID[client.id] == nil else {
            throw ClientStoreError.clientAlreadyExists
        }
        clientsByID[client.id] = client
        clientIDsByUserEmail[client.user.email, default: []].append(client.id)
    }

    /// Returns the client registered under `id`, or `nil` if none.
    public func client(id: Client.ID) -> Client? {
        clientsByID[id]
    }

    /// Returns every client owned by the user with `userEmail`, in
    /// creation order, or an empty array if the user owns none.
    public func allClients(for userEmail: EmailAddress) -> [Client] {
        clientIDsByUserEmail[userEmail, default: []].compactMap { clientsByID[$0] }
    }
}
