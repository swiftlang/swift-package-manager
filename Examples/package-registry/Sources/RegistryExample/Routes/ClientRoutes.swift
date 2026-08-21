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

import Foundation
import Vapor

/// Route handlers for managing the clients on the calling account:
/// `POST /clients`, `GET /clients`, and `DELETE /clients/{id}`.
///
/// Like `POST /users`, these endpoints are registry-specific. They aren't part of 
/// the SE-0292 API surface. They exist because an account is not one credential: 
/// a user may hold one token per machine or automation.
///
/// `POST` mints for
/// whoever authenticated, `GET` lists only their clients, and `DELETE` refuses
/// any id registered to another account with the same `404` it returns for an
/// id registered to nobody. The response cannot be used to discover which
/// clients exist elsewhere.
///
/// Revocation takes effect immediately, because ``ClientResolver`` re-reads the
/// ``ClientStore`` on every request rather than trusting what verified earlier.
/// A caller that revokes the client it is calling with therefore finds its next
/// request unauthenticated.
///
/// What a caller may not do is revoke the last client on its account: with
/// nothing left to authenticate as, the account would be unusable and this
/// registry offers no way back into it. That attempt is a `409 Conflict`.``
public struct ClientRoutes: Sendable {
    let resolver: ClientResolver
    let registrar: ClientRegistrar
    let store: ClientStore

    /// Creates a `ClientRoutes` handler.
    ///
    /// - Parameters:
    ///   - resolver: Resolves which client is calling.
    ///   - registrar: Registers the newly minted clients.
    ///   - store: The store listed and revoked from.
    public init(resolver: ClientResolver, registrar: ClientRegistrar, store: ClientStore) {
        self.resolver = resolver
        self.registrar = registrar
        self.store = store
    }

    /// Registers the client management routes on `router`.
    ///
    /// - Parameter router: A router expected to be gated by
    ///   ``ClientAuthenticator``, so a request reaching a handler with valid
    ///   credentials already carries an ``AuthenticatedClient``.
    public func register(_ router: any RoutesBuilder) {
        router.get("clients", use: list)
        router.post("clients", use: mint)
        router.delete("clients", ":id", use: revoke)
    }

    @Sendable
    func list(req: Request) async throws -> Response {
        let clients = await store.clients(for: try await callingUser(req))
        return try json(
            ClientListResponse(
                clients: clients.map { ClientListResponse.Client(id: $0.id.value, method: $0.method) }
            ),
            status: .ok
        )
    }

    @Sendable
    func mint(req: Request) async throws -> Response {
        let registration = try await registrar.registerBearerClient(for: try await callingUser(req))
        let id = registration.client.id
        let response = try json(
            MintedClientResponse(id: id.value, token: registration.token),
            status: .created
        )
        response.headers.replaceOrAdd(name: .location, value: "\(req.baseURL)/clients/\(id.value)")
        return response
    }

    @Sendable
    func revoke(req: Request) async throws -> Response {
        let user = try await callingUser(req)
        let id = ClientID(try req.parameters.require("id"))
        do {
            try await store.revoke(id, of: user)
        } catch ClientStoreError.noSuchClient {
            throw ProblemDetails.notFound("no such client")
        } catch ClientStoreError.lastRemainingClient {
            throw ProblemDetails.conflict(
                "an account must keep at least one client; register another before revoking this one"
            )
        }
        return Response(status: .noContent)
    }

    private func callingUser(_ req: Request) async throws -> User {
        guard let user = await resolver.user(authenticating: req) else {
            throw ProblemDetails.missingOrInvalidCredentials
        }
        return user
    }

    private func json(_ payload: some Encodable, status: HTTPResponseStatus) throws -> Response {
        let data = try JSONEncoder.registry.encode(payload)
        let response = Response(status: status, body: .init(data: data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        return response
    }
}

/// The `POST /clients` success body.
///
/// ``token`` is the plaintext the caller must persist: the registry stores only
/// its hash, so this is the one and only time it is readable.
struct MintedClientResponse: Encodable {
    var id: String
    var token: String
}

/// The `GET /clients` success body: what the account holds, with no credential
/// material in it.
struct ClientListResponse: Encodable {
    struct Client: Encodable {
        var id: String
        var method: String
    }

    var clients: [Client]
}
