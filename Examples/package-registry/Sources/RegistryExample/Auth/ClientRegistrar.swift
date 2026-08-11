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

/// Errors thrown by ``ClientRegistrar``.
public enum ClientRegistrationError: Error, Equatable, Sendable {
    /// A `password` field was present but empty.
    case emptyPassword
    /// The user already holds a Basic client. A second one would give the
    /// account a second username and password, which the registry does not
    /// allow — rotate the existing client's password instead.
    case userAlreadyHasBasicClient
}

/// The outcome of registering a Bearer client.
///
/// ``token`` carries the freshly minted plaintext that the caller must
/// persist — it is returned exactly once and never recoverable afterward,
/// since the store keeps only its hash.
public struct BearerClientRegistration: Sendable, Equatable {
    /// The newly registered client.
    public let client: RegisteredClient<BearerAuth>
    /// The one-time plaintext token.
    public let token: String
}

/// Registers new ``RegisteredClient``s for existing users.
///
/// The registrar owns all credential preparation — bcrypt password hashing and
/// token generation — so that ``ClientStore/store(_:)`` stays a synchronous,
/// atomic insert. Password hashing is offloaded to the shared thread pool so
/// bcrypt's CPU cost never blocks the event loop serving other requests.
/// Mirrors ``UserRegistrar``.
///
/// How many clients a user may hold is not the registrar's rule to invent:
/// each authentication method already declares it through what it puts in
/// its credentials, and the store enforces it. ``BearerAuth`` keys on a
/// per-token value, so a user can register as many as they have machines.
/// ``BasicAuth`` keys on the user's email alone, so the second Basic client
/// for one account collides with the first — the registrar's only added work
/// there is translating that collision into
/// ``ClientRegistrationError/userAlreadyHasBasicClient``, which says why it
/// happened.
public struct ClientRegistrar: Sendable {
    let store: ClientStore
    let tokenGenerator: TokenGenerator
    let idGenerator: ClientIDGenerator

    /// Creates a registrar backed by `store`.
    ///
    /// - Parameters:
    ///   - store: The client store to insert into.
    ///   - tokenGenerator: The source of minted bearer tokens. Defaults to
    ///     the system CSPRNG; tests inject a deterministic generator.
    ///   - idGenerator: The source of minted ``ClientID``s. Defaults to random
    ///     UUIDs; tests inject a deterministic generator.
    public init(
        store: ClientStore,
        tokenGenerator: TokenGenerator = .secureRandom,
        idGenerator: ClientIDGenerator = .random
    ) {
        self.store = store
        self.tokenGenerator = tokenGenerator
        self.idGenerator = idGenerator
    }

    /// Registers the user's one HTTP Basic client.
    ///
    /// - Parameters:
    ///   - user: The account the client acts for. Its email doubles as the
    ///     Basic username.
    ///   - password: The chosen password, stored only as a bcrypt hash.
    /// - Returns: The registered client.
    /// - Throws: ``ClientRegistrationError/emptyPassword`` for an empty
    ///   password, or
    ///   ``ClientRegistrationError/userAlreadyHasBasicClient`` if the user
    ///   already holds one.
    public func registerBasicClient(
        for user: User,
        password: String
    ) async throws -> RegisteredClient<BasicAuth> {
        guard !password.isEmpty else {
            throw ClientRegistrationError.emptyPassword
        }
        let client = RegisteredClient.basic(
            id: idGenerator.makeID(),
            user: user,
            passwordHash: try await Self.hashPassword(password)
        )
        do {
            return try await store(client)
        } catch ClientStoreError.clientAlreadyExists {
            throw ClientRegistrationError.userAlreadyHasBasicClient
        }
    }

    /// Registers a Bearer client, minting its token.
    ///
    /// A user may hold any number of these, one per machine or automation.
    ///
    /// - Parameter user: The account the client acts for.
    /// - Returns: The registered client and its one-time plaintext token.
    /// - Throws: ``ClientStoreError/clientAlreadyExists`` if the minted token
    ///   collides with a registered one, or
    ///   ``ClientStoreError/idAlreadyExists`` if the minted id does. With
    ///   256-bit tokens and UUID ids either is astronomically unlikely and is
    ///   treated as a server-side condition rather than a client error.
    public func registerBearerClient(for user: User) async throws -> BearerClientRegistration {
        let token = tokenGenerator.makeToken()
        let client = try await store(
            RegisteredClient.bearer(id: idGenerator.makeID(), user: user, token: token)
        )
        return BearerClientRegistration(client: client, token: token)
    }

    private func store<Auth: AuthenticationMethod>(
        _ client: RegisteredClient<Auth>
    ) async throws -> RegisteredClient<Auth> {
        try await store.store(client)
        return client
    }

    private static func hashPassword(_ password: String) async throws -> String {
        try await NIOThreadPool.singleton.runIfActive {
            try Bcrypt.hash(password)
        }
    }
}
