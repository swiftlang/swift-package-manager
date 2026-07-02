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

/// Middleware that admits a request only when some user is logged in.
public struct RequireLoginMiddleware: AsyncMiddleware {
    let session: LoginSession

    /// Creates the middleware backed by the given login session.
    ///
    /// - Parameter session: The session consulted for a logged-in user.
    public init(session: LoginSession) {
        self.session = session
    }

    /// Forwards the request downstream only when a user is logged in.
    ///
    /// - Parameters:
    ///   - request: The incoming request.
    ///   - next: The downstream responder invoked when a user is logged in.
    /// - Returns: The downstream response.
    /// - Throws: ``ProblemDetails`` `401 Unauthorized` when no user is
    ///   logged in.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Users don't own packages in this example registry, 
        // We don't track which user is logged in to the registry
        // As long as some user is logged in during this session, publishing is allowed
        guard await session.hasActiveUser else {
            throw ProblemDetails.unauthorized("login required to publish")
        }
        return try await next.respond(to: request)
    }
}
