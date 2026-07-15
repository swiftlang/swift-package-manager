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
/// scheme dispatch and the `401`-vs-`501` distinction are shared with the
/// publish gate via ``UserAuthenticator/authenticate(_:)``, so the same
/// credentials that log in also authorize publishing.
///
/// All failures are thrown as ``ProblemDetails`` so the error carries the
/// `application/problem+json` body (and, for `401`, the `WWW-Authenticate`
/// header) that the registry error contract requires.
public struct LoginRoutes: Sendable {
    let authenticator: UserAuthenticator

    /// Creates a `LoginRoutes` handler.
    ///
    /// - Parameter authenticator: Verifies the presented credentials.
    public init(authenticator: UserAuthenticator) {
        self.authenticator = authenticator
    }

    /// Registers `POST /login` on `router`.
    public func register(_ router: any RoutesBuilder) {
        router.post("login", use: login)
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        _ = try await authenticator.authenticate(req)
        return Response(status: .ok)
    }
}
