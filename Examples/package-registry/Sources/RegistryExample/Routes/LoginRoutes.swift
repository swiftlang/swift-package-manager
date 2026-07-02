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
/// email:password>`) and Bearer (`Authorization: Bearer <token>`). The
/// three outcomes cannot be distinguished from Vapor's
/// `basicAuthorization`/`bearerAuthorization` accessors alone — both return
/// `nil` for an absent header, an unsupported scheme, *and* malformed
/// credentials — so the handler first reads the raw scheme: an absent
/// header is `401`, a recognized scheme with bad credentials is `401`, and
/// only a genuinely unsupported scheme (for example `Digest`) is `501`.
/// The scheme token is matched case-insensitively per RFC 7235.
///
/// All failures are thrown as ``ProblemDetails`` so the error carries the
/// `application/problem+json` body (and, for `401`, the `WWW-Authenticate`
/// header) that the registry error contract requires.
public struct LoginRoutes: Sendable {
    let authenticator: UserAuthenticator
    let session: LoginSession

    /// Creates a `LoginRoutes` handler.
    ///
    /// - Parameters:
    ///   - authenticator: Verifies the presented credentials.
    ///   - session: Records the authenticated user so that (when enabled)
    ///     the publish endpoint can see that a user is logged in.
    public init(authenticator: UserAuthenticator, session: LoginSession) {
        self.authenticator = authenticator
        self.session = session
    }

    /// Registers `POST /login` on `router`.
    public func register(_ router: any RoutesBuilder) {
        router.post("login", use: login)
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        guard let header = req.headers.first(name: .authorization) else {
            throw ProblemDetails.unauthorized("authentication required")
        }
        let scheme = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        switch scheme?.lowercased() {
        case "basic":
            return try await authenticateBasic(req)
        case "bearer":
            return try await authenticateBearer(req)
        default:
            throw ProblemDetails.notImplemented("unsupported authentication method")
        }
    }

    private func authenticateBasic(_ req: Request) async throws -> Response {
        guard let basic = req.headers.basicAuthorization,
              let email = await authenticator.authenticate(email: basic.username, password: basic.password)
        else {
            throw ProblemDetails.unauthorized("invalid credentials")
        }
        await session.logIn(email)
        return Response(status: .ok)
    }

    private func authenticateBearer(_ req: Request) async throws -> Response {
        guard let bearer = req.headers.bearerAuthorization,
              let email = await authenticator.authenticate(token: bearer.token)
        else {
            throw ProblemDetails.unauthorized("invalid credentials")
        }
        await session.logIn(email)
        return Response(status: .ok)
    }
}
