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

/// Route handler for `POST /login` — the SwiftPM registry login API.
///
/// SwiftPM's `login` subcommand POSTs an `Authorization` header for the
/// registry to validate, and keys its behavior off the status code:
///
/// - `200 OK` — credentials are valid; SwiftPM persists them.
/// - `401 Unauthorized` — credentials are missing or invalid.
/// - `501 Not Implemented` — the presented authentication *method* is not
///   supported by this registry.
///
/// This registry supports HTTP Basic (`Authorization: Basic <base64
/// email:password>`) and Bearer (`Authorization: Bearer <token>`).
/// Verification is performed by ``ClientAuthenticator`` acting as an
/// `AsyncRequestAuthenticator` middleware on the route group: it logs in an
/// ``AuthenticatedClient`` when the credentials are valid, or throws
/// `501 Not Implemented` for an unsupported scheme. The handler then resolves
/// that client back to its account through ``ClientResolver``, so credentials
/// that never verified — or that name a client no longer registered — surface
/// as `401 Unauthorized`. The same middleware gates publishing, so the
/// credentials that log in also authorize publishing.
///
/// Because the account is resolved from the client rather than carried by the
/// credential, every one of a user's clients logs in as that same user: their
/// password and each of their tokens all report one email.
///
/// Failures reach the client as ``ProblemDetails`` (via
/// ``ProblemErrorMiddleware``), carrying the `application/problem+json`
/// body — and, for `401`, the `WWW-Authenticate` header — that the registry
/// error contract requires.
public struct LoginRoutes: Sendable {
    let resolver: ClientResolver

    /// Creates a `LoginRoutes` handler.
    ///
    /// - Parameter resolver: Resolves the calling client's account.
    public init(resolver: ClientResolver) {
        self.resolver = resolver
    }

    /// Registers `POST /login` on `router`.
    ///
    /// - Parameter router: A router expected to be gated by
    ///   ``ClientAuthenticator``, so a request reaching ``login(req:)`` with
    ///   valid credentials already carries an ``AuthenticatedClient``.
    public func register(_ router: any RoutesBuilder) {
        router.post("login", use: login)
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        guard let user = await resolver.user(authenticating: req) else {
            throw ProblemDetails.missingOrInvalidCredentials
        }
        let data = try JSONEncoder.registry.encode(LoginResponse(email: user.email.value))
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        return response
    }
}

/// The `POST /login` success body, echoing the identity that authenticated.
///
/// SwiftPM's `login` subcommand keys only off the status code, so the body is
/// advisory — but returning the resolved email lets a caller confirm *which*
/// account a credential maps to.
struct LoginResponse: Encodable {
    var email: String
}
