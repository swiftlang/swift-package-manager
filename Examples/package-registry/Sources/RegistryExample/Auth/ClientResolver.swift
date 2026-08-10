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

/// Resolves the account behind whichever client authenticated a request.
///
/// ``ClientAuthenticator`` establishes *which client* is calling by logging in
/// an ``AuthenticatedClient`` specialized to the method that verified, and
/// Vapor's authentication cache is keyed by concrete type — so a request
/// carrying an `AuthenticatedClient<BasicAuth>` answers nothing about
/// `AuthenticatedClient<BearerAuth>`. "Who is calling?" is therefore a question
/// about a *set* of types, and this resolver is the one place that set is
/// written down: making a new authentication method resolvable means adding a
/// line to ``user(authenticating:)``.
///
/// Resolution re-reads the ``ClientStore`` every time it is asked rather than
/// trusting anything captured when the credentials verified. A client
/// unregistered between authenticating and being resolved has no user, which
/// is what lets a guard reject it.
///
/// The user is deliberately looked up *through* the client rather than carried
/// by it, because many clients may point back to one account: a developer's
/// password, their laptop's certificate, and a CI token are separate clients
/// of the same user, each free to differ in what it is allowed to do.
public struct ClientResolver: Sendable {
    let store: ClientStore

    /// Creates a resolver backed by `store`.
    ///
    /// - Parameter store: The client store consulted on every resolution.
    public init(store: ClientStore) {
        self.store = store
    }

    /// The user on whose behalf `request`'s authenticated client is acting.
    ///
    /// - Parameter request: A request that has passed through
    ///   ``ClientAuthenticator``.
    /// - Returns: The calling client's user, or `nil` when no supported method
    ///   authenticated `request` or the client it authenticated is no longer
    ///   registered.
    public func user(authenticating request: Request) async -> User? {
        if let user = await user(of: BasicAuth.self, authenticating: request) { return user }
        return await user(of: BearerAuth.self, authenticating: request)
    }

    private func user<Auth: AuthenticationMethod>(
        of _: Auth.Type,
        authenticating request: Request
    ) async -> User? {
        guard let client = request.auth.get(AuthenticatedClient<Auth>.self) else { return nil }
        return await store.client(ofType: Auth.self, for: client.credentials)?.user
    }
}
