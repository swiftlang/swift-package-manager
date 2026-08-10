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

/// Rejects a request that no supported authentication method authenticated.
///
/// Vapor's `Authenticatable.guardMiddleware()` guards exactly one concrete
/// type, which cannot express "authenticated by *any* of the registry's
/// methods" now that ``AuthenticatedClient`` is specialized per method. This
/// middleware asks ``ClientResolver`` instead, so one guard admits a Basic
/// client and a Bearer one — and, because the resolver re-reads the
/// ``ClientStore``, turns a client whose registration has since been withdrawn
/// away too.
///
/// Absent, invalid, and no-longer-registered credentials all produce the same
/// `401`, so a rejected caller learns nothing about which accounts or
/// credentials exist.
public struct AuthenticatedClientGuardMiddleware: AsyncMiddleware {
    let resolver: ClientResolver

    /// Creates a guard that admits any client `resolver` can resolve.
    ///
    /// - Parameter resolver: Resolves the calling client's account.
    public init(resolver: ClientResolver) {
        self.resolver = resolver
    }

    /// Forwards the request downstream when an authenticated client resolves.
    ///
    /// - Parameters:
    ///   - request: The incoming request, expected to have passed through
    ///     ``ClientAuthenticator``.
    ///   - next: The responder to invoke once the request is authenticated.
    /// - Returns: The response produced by `next`.
    /// - Throws: ``ProblemDetails/missingOrInvalidCredentials`` when no
    ///   registered client authenticated the request.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard await resolver.user(authenticating: request) != nil else {
            throw ProblemDetails.missingOrInvalidCredentials
        }
        return try await next.respond(to: request)
    }
}
