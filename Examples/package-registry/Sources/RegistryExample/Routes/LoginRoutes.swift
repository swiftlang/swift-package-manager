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
/// Verification is performed by ``UserAuthenticator`` acting as an
/// `AsyncRequestAuthenticator` middleware on the route group: it logs in an
/// ``AuthenticatedUser`` when the credentials are valid, or throws
/// `501 Not Implemented` for an unsupported scheme. The handler then
/// *requires* that authenticated user, so missing or invalid credentials
/// surface as `401 Unauthorized`. The same middleware gates publishing, so
/// the credentials that log in also authorize publishing.
///
/// Failures reach the client as ``ProblemDetails`` (via
/// ``ProblemErrorMiddleware``), carrying the `application/problem+json`
/// body — and, for `401`, the `WWW-Authenticate` header — that the registry
/// error contract requires.
public struct LoginRoutes: Sendable {
    /// Creates a `LoginRoutes` handler.
    public init() {}

    /// Registers `POST /login` on `router`.
    ///
    /// - Parameter router: A router expected to be gated by
    ///   ``UserAuthenticator``, so a request reaching ``login(req:)`` with
    ///   valid credentials already carries an ``AuthenticatedUser``.
    public func register(_ router: any RoutesBuilder) {
        router.post("login", use: login)
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        _ = try req.auth.require(AuthenticatedUser.self)
        return Response(status: .ok)
    }
}
