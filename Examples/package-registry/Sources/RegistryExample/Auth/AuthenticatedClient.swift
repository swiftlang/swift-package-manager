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

/// The identity established once a request's credentials verify.
///
/// Different from the ``RegisteredClient`` model since this struct is only
/// used when the client is authenticated. The ``RegisteredClient`` model is
/// for all clients that have ever been registered.
///
/// Only the credentials are carried, not the resolved ``RegisteredClient``.
/// Verifying a credential proves *which* client is calling; the client's user
/// and permissions are whatever the ``ClientStore`` says they are at the
/// moment a handler asks, so resolution is left to the handler — via
/// ``ClientStore/client(ofType:for:)`` — rather than snapshotted at login. A
/// revoked or re-scoped client therefore cannot be used by a request that
/// authenticated before the change.
///
/// The generic parameter keeps each authentication method in its own slot of
/// Vapor's authentication cache, which is keyed by concrete type: a request
/// carrying an `AuthenticatedClient<MutualTLS>` does not satisfy a
/// `require(AuthenticatedClient<SomeOtherMethod>.self)`. A method's
/// credentials are likewise only ever matched against clients registered
/// under that same method.
public struct AuthenticatedClient<Auth: AuthenticationMethod>: Authenticatable, Sendable, Equatable {
    /// The verified credentials identifying the calling client.
    public let credentials: Auth.Credentials

    /// Creates an authenticated client identified by `credentials`.
    ///
    /// - Parameter credentials: The credentials that have already been
    ///   verified for this request.
    public init(credentials: Auth.Credentials) {
        self.credentials = credentials
    }
}
