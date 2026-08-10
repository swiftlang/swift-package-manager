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
import X509

/// Errors thrown by ``ClientRegistrar``.
public enum ClientRegistrationError: Error, Equatable, Sendable {
    /// A `password` field was present but empty.
    case emptyPassword
    /// The user already holds a Basic client. A second one would give the
    /// account a second username and password, which the registry does not
    /// allow — rotate the existing client's password instead.
    case userAlreadyHasBasicClient
    /// A client is already registered under this certificate, whether or not
    /// it belongs to the same user.
    case certificateAlreadyRegistered
}

/// The outcome of registering a Bearer client.
///
/// ``token`` carries the freshly minted plaintext that the caller must
/// persist — it is returned exactly once and never recoverable afterward,
/// since the store keeps only its hash.
public struct BearerClientRegistration: Sendable, Equatable {
    /// The newly registered client.
    public let client: Client<BearerAuth>
    /// The one-time plaintext token.
    public let token: String
}

/// Registers new ``Client``s for existing users.
///
/// The registrar owns all credential preparation — bcrypt password hashing,
/// token generation, certificate thumbprinting — so that
/// ``ClientStore/store(_:)`` stays a synchronous, atomic insert. Password
/// hashing is offloaded to the shared thread pool so bcrypt's CPU cost never
/// blocks the event loop serving other requests. Mirrors ``UserRegistrar``.
///
/// How many clients a user may hold is not the registrar's rule to invent:
/// each authentication method already declares it through what it puts in
/// its credentials, and the store enforces it. Bearer and mutual TLS key on
/// a per-token and per-certificate value, so a user can register as many as
/// they have machines. ``BasicAuth`` keys on the user's email alone, so the
/// second Basic client for one account collides with the first — the
/// registrar's only added work there is translating that collision into
/// ``ClientRegistrationError/userAlreadyHasBasicClient``, which says why it
/// happened.
public struct ClientRegistrar: Sendable {
    let store: ClientStore
    let tokenGenerator: TokenGenerator

    /// Creates a registrar backed by `store`.
    ///
    /// - Parameters:
    ///   - store: The client store to insert into.
    ///   - tokenGenerator: The source of minted bearer tokens. Defaults to
    ///     the system CSPRNG; tests inject a deterministic generator.
    public init(store: ClientStore, tokenGenerator: TokenGenerator = .secureRandom) {
        self.store = store
        self.tokenGenerator = tokenGenerator
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
    public func registerBasicClient(for user: User, password: String) async throws -> Client<BasicAuth> {
        guard !password.isEmpty else {
            throw ClientRegistrationError.emptyPassword
        }
        let client = AuthMethods.Basic.client(user: user, passwordHash: try await Self.hashPassword(password))
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
    ///   collides with a registered one. With 256-bit tokens this is
    ///   astronomically unlikely and is treated as a server-side condition
    ///   rather than a client error.
    public func registerBearerClient(for user: User) async throws -> BearerClientRegistration {
        let token = tokenGenerator.makeToken()
        let client = try await store(AuthMethods.Bearer.client(user: user, token: token))
        return BearerClientRegistration(client: client, token: token)
    }

    /// Registers a mutual TLS client for a certificate.
    ///
    /// A user may hold any number of these, one per certificate.
    ///
    /// - Parameters:
    ///   - user: The account the client acts for.
    ///   - certificate: The client certificate, identified by its thumbprint.
    ///   - rootCertificateAuthority: The trust anchor the certificate is
    ///     accepted under.
    /// - Returns: The registered client.
    /// - Throws: ``ClientRegistrationError/certificateAlreadyRegistered`` if
    ///   a client is already registered under this certificate, or an
    ///   `ASN1Error` if the certificate cannot be thumbprinted.
    public func registerMutualTLSClient(
        for user: User,
        certificate: Certificate,
        rootCertificateAuthority: RootCertificateAuthority
    ) async throws -> Client<MutualTLS> {
        let client = try AuthMethods.MTLS.client(
            user: user,
            rootCertificateAuthority: rootCertificateAuthority,
            certificate: certificate
        )
        do {
            return try await store(client)
        } catch ClientStoreError.clientAlreadyExists {
            throw ClientRegistrationError.certificateAlreadyRegistered
        }
    }

    private func store<Auth: AuthenticationMethod>(_ client: Client<Auth>) async throws -> Client<Auth> {
        try await store.store(client)
        return client
    }

    private static func hashPassword(_ password: String) async throws -> String {
        try await NIOThreadPool.singleton.runIfActive {
            try Bcrypt.hash(password)
        }
    }
}
