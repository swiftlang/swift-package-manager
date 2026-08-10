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

private enum AuthorizationScheme: String {
    case basic
    case bearer
}

extension ClientAuthenticator: AsyncRequestAuthenticator {
    /// Populates `request.auth` with an ``AuthenticatedClient`` — specialized
    /// to whichever authentication method verified — when the request carries
    /// valid credentials.
    ///
    /// Each method fills its own slot of Vapor's authentication cache, so a
    /// request that verified a Basic credential is authenticated as an
    /// `AuthenticatedClient<BasicAuth>` and nothing else. Two clients of the
    /// same user therefore never stand in for one another.
    ///
    /// This follows Vapor's authenticator contract: a missing `Authorization`
    /// header or credentials that fail to verify leave the request
    /// *unauthenticated* rather than failing here. Rejecting such requests is
    /// the job of a downstream guard — ``AuthenticatedClientGuardMiddleware``
    /// on the publish group, or ``ClientResolver`` in the login handler —
    /// which surfaces the absence as `401 Unauthorized`.
    ///
    /// The single exception is an *unsupported scheme*, which cannot be
    /// modeled as "unauthenticated": it is thrown as `501 Not Implemented` so
    /// the registry distinguishes an authentication method it does not
    /// support from credentials it rejects.
    ///
    /// - Parameter request: The request whose `Authorization` header is
    ///   inspected.
    /// - Throws: ``ProblemDetails`` `501 Not Implemented` when the
    ///   authentication scheme is unsupported.
    public func authenticate(request: Request) async throws {
        guard let authHeader = request.headers.first(name: .authorization) else {
            return
        }

        let scheme = authHeader.prefix(while: { !$0.isWhitespace }).lowercased()

        switch AuthorizationScheme(rawValue: scheme) {
        case .basic:
            guard let basic = request.headers.basicAuthorization,
                  let credentials = await authenticate(email: basic.username, password: basic.password)
            else { return }
            request.auth.login(AuthenticatedClient<BasicAuth>(credentials: credentials))

        case .bearer:
            guard let bearer = request.headers.bearerAuthorization,
                  let credentials = await authenticate(token: bearer.token)
            else { return }
            request.auth.login(AuthenticatedClient<BearerAuth>(credentials: credentials))

        case nil:
            throw ProblemDetails.notImplemented("Unsupported authentication scheme")
        }
    }
}
