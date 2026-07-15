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

/// Middleware that admits a request only when it carries valid credentials.
public struct RequireLoginMiddleware: AsyncMiddleware {
    let authenticator: UserAuthenticator

    /// Creates the middleware backed by the given authenticator.
    ///
    /// - Parameter authenticator: Verifies the credentials presented on each
    ///   request.
    public init(authenticator: UserAuthenticator) {
        self.authenticator = authenticator
    }

    /// Forwards the request downstream only when it presents valid
    /// credentials, re-verifying them on every request rather than trusting
    /// a prior login.
    ///
    /// - Parameters:
    ///   - request: The incoming request.
    ///   - next: The downstream responder invoked when the credentials are
    ///     valid.
    /// - Returns: The downstream response.
    /// - Throws: ``ProblemDetails`` `401 Unauthorized` when credentials are
    ///   absent or invalid, or `501 Not Implemented` when the authentication
    ///   method is unsupported.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        _ = try await authenticator.authenticate(request)
        return try await next.respond(to: request)
    }
}
