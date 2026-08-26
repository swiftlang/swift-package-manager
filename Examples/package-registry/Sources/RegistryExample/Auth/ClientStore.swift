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

/// Errors thrown by ``ClientStore``.
public enum ClientStoreError: Error, Equatable, Sendable {
    /// A client is already registered under the same credentials. What that
    /// means is the authentication method's choice — a second Basic client
    /// for one email, a colliding bearer token.
    case clientAlreadyExists
    /// A client is already registered under the same ``ClientID``. Distinct
    /// from ``clientAlreadyExists`` because the credentials were free: the
    /// remedy is a fresh id, not a rejected registration.
    case idAlreadyExists
    /// The account has no client under the given ``ClientID``. One error for an
    /// id registered to nobody and one registered to another account, so a
    /// caller cannot use revocation to discover other accounts' clients.
    case noSuchClient
    /// The client is the last one its account holds, and revoking it would
    /// leave the account with nothing to authenticate as.
    case lastRemainingClient
}

/// An in-memory, actor-isolated store of every ``RegisteredClient``.
///
/// Clients are reached two ways, so the store keeps two indexes over one set of
/// entries. Authentication looks a client up by the credentials presented,
/// which is all a password or token can be matched against. Management looks it
/// up by ``ClientID``, the public name under which a user can list what is
/// registered to their account and revoke one of them.
//
/// Entries are keyed by authentication method *and* credentials, which is what
/// lets each method decide how many clients one user may hold: ``BearerAuth``
/// keys on a per-token value, so a user can register a token per machine, while
/// ``BasicAuth`` keys on the email alone, so a second password client for one
/// account collides with the first. All state is ephemeral.
public actor ClientStore {
    /// A client's method and credentials together, the key authentication
    /// resolves by.
    private struct CredentialsKey: Hashable {
        let method: ObjectIdentifier
        let credentials: AnyHashable
    }

    /// One registered client: its erased self for typed retrieval, the summary
    /// that describes it without credentials, and the credentials key to
    /// withdraw from the authentication index when it is revoked.
    private struct Entry {
        let client: any Sendable
        let summary: ClientSummary
        let credentialsKey: CredentialsKey
    }

    private var entriesByID: [ClientID: Entry] = [:]
    private var idsByCredentials: [CredentialsKey: ClientID] = [:]
    private var idsByUser: [EmailAddress: [ClientID]] = [:]

    public init() {}

    /// Registers `client` under its credentials, its id, and its user.
    ///
    /// - Parameter client: The client to persist.
    /// - Throws: ``ClientStoreError/clientAlreadyExists`` if a client is
    ///   already stored under the same method and credentials, or
    ///   ``ClientStoreError/idAlreadyExists`` if one already holds the same
    ///   ``ClientID``. Either way the existing client is left untouched and
    ///   nothing is inserted.
    public func store<Auth: AuthenticationMethod>(_ client: RegisteredClient<Auth>) throws {
        let credentialsKey = Self.credentialsKey(ofType: Auth.self, for: client.auth.credentials)
        guard idsByCredentials[credentialsKey] == nil else {
            throw ClientStoreError.clientAlreadyExists
        }
        guard entriesByID[client.id] == nil else {
            throw ClientStoreError.idAlreadyExists
        }
        entriesByID[client.id] = Entry(
            client: client,
            summary: client.summary,
            credentialsKey: credentialsKey
        )
        idsByCredentials[credentialsKey] = client.id
        idsByUser[client.user.email, default: []].append(client.id)
    }

    public func client<Auth: AuthenticationMethod>(
        ofType _: Auth.Type,
        for credentials: Auth.Credentials
    ) -> RegisteredClient<Auth>? {
        let credentialsKey = Self.credentialsKey(ofType: Auth.self, for: credentials)
        guard let id = idsByCredentials[credentialsKey] else { return nil }
        return entriesByID[id]?.client as? RegisteredClient<Auth>
    }

    /// Every client registered to `user`, in the order they were registered.
    ///
    /// Summaries rather than clients, because a user's clients are of differing
    /// authentication methods and so of differing types — and because what a
    /// listing is for is telling a user what exists, which never requires
    /// handing back the credentials that verify them.
    ///
    /// - Parameter user: The account whose clients to list.
    /// - Returns: The user's clients, or an empty array if they hold none.
    public func clients(for user: User) -> [ClientSummary] {
        (idsByUser[user.email] ?? []).compactMap { entriesByID[$0]?.summary }
    }

    /// Withdraws the registration of the client `id` names.
    ///
    /// An id registered to anyone else is indistinguishable from one registered
    /// to nobody, so a caller cannot use revocation to discover which clients
    /// exist on other accounts.
    ///
    /// An account must keep at least one client, so its last one cannot be
    /// revoked: nothing could authenticate as that user afterwards.
    ///
    /// - Parameters:
    ///   - id: The public name of the client to revoke.
    ///   - user: The account that must own it.
    /// - Returns: The revoked client's summary.
    /// - Throws: ``ClientStoreError/noSuchClient`` when `user` has no client
    ///   under `id`, or ``ClientStoreError/lastRemainingClient`` when it is the
    ///   only client they hold. Either way nothing is removed.
    @discardableResult
    public func revoke(_ id: ClientID, of user: User) throws -> ClientSummary {
        guard let entry = entriesByID[id], entry.summary.user == user else {
            throw ClientStoreError.noSuchClient
        }
        guard (idsByUser[user.email] ?? []).count > 1 else {
            throw ClientStoreError.lastRemainingClient
        }
        entriesByID[id] = nil
        idsByCredentials[entry.credentialsKey] = nil
        idsByUser[user.email]?.removeAll { $0 == id }
        return entry.summary
    }

    private static func credentialsKey<Auth: AuthenticationMethod>(
        ofType _: Auth.Type,
        for credentials: Auth.Credentials
    ) -> CredentialsKey {
        CredentialsKey(method: ObjectIdentifier(Auth.self), credentials: AnyHashable(credentials))
    }
}
