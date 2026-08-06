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

/// Transparently implements support for `HEAD` requests on endpoints that
/// only declare a `GET` handler.
///
/// The Swift Package Registry specification (§4 *Endpoints*) states:
///
/// > A server SHOULD also respond to `HEAD` requests for each of the
/// > specified endpoints.
///
/// Rather than registering a separate route for every endpoint, this
/// middleware intercepts incoming `HEAD` requests, temporarily rewrites the
/// method to `GET` so that the existing route handler runs, and then discards
/// the response body before returning, producing a response whose headers
/// match the equivalent `GET` request but which carries no payload, as
/// required by [RFC 9110 §9.3.2][].
///
/// The original `HEAD` method is restored on the request before the response
/// is returned (and also if the downstream responder throws), so that other
/// middleware and logging see the client's original intent. Downstream
/// components that inspect `request.method` (for example,
/// ``ProblemErrorMiddleware`` suppressing problem-detail bodies for `HEAD`
/// requests) continue to observe `HEAD`.
///
/// [RFC 9110 §9.3.2]: https://www.rfc-editor.org/rfc/rfc9110#section-9.3.2
public struct HeadMethodMiddleware: AsyncMiddleware {
    /// Creates a new `HeadMethodMiddleware`.
    public init() {}

    /// Handles `HEAD` requests by dispatching them to the corresponding `GET`
    /// handler and stripping the response body.
    ///
    /// Non-`HEAD` requests are forwarded unchanged.
    ///
    /// - Parameters:
    ///   - request: The incoming request. If its method is `HEAD`, the method
    ///     is temporarily rewritten to `GET` for the duration of the
    ///     downstream call and restored before this method returns, whether
    ///     the downstream responder succeeds or throws.
    ///   - next: The responder that will handle the (possibly rewritten)
    ///     request.
    /// - Returns: The downstream response, with its body cleared when the
    ///   original request was a `HEAD` request.
    /// - Throws: Re-throws any error produced by the downstream responder.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.method == .HEAD else {
            return try await next.respond(to: request)
        }
        request.method = .GET
        let response: Response
        do {
            response = try await next.respond(to: request)
        } catch {
            request.method = .HEAD
            throw error
        }
        request.method = .HEAD
        response.body = .empty
        return response
    }
}
