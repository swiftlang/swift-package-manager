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

/// Translates thrown errors into RFC 7807 "problem details" responses.
///
/// The Swift Package Registry specification (§3.3 *Error handling*) requires
/// that servers communicate errors using problem detail objects, for example:
///
/// ```http
/// HTTP/1.1 404
/// Content-Version: 1
/// Content-Type: application/problem+json
/// Content-Language: en
///
/// {
///    "detail": "release not found"
/// }
/// ```
///
/// This middleware converts any error thrown by downstream responders into a
/// response that satisfies the contract:
///
/// - ``ProblemDetails`` errors are serialized as-is, preserving their
///   HTTP status.
/// - Vapor `AbortError`s are wrapped in a ``ProblemDetails`` using the
///   abort's `status` and `reason`.
/// - All other errors are reported to the request's logger and surfaced as a
///   `500 Internal Server Error` problem with the generic detail
///   `"internal server error"`, so that implementation details are never
///   leaked to clients.
///
/// Every generated response sets `Content-Type: application/problem+json`,
/// `Content-Language: en`, and `Content-Version: 1`, matching the headers
/// prescribed by the specification. If JSON encoding of the problem itself
/// fails, a minimal hand-written JSON body is returned as a last-resort
/// fallback so that the client always receives a well-formed body.
///
/// When the originating request used the `HEAD` method, the response body is
/// cleared before returning, matching the semantics enforced by
/// ``HeadMethodMiddleware`` and [RFC 9110 §9.3.2][].
///
/// [RFC 9110 §9.3.2]: https://www.rfc-editor.org/rfc/rfc9110#section-9.3.2
public struct ProblemErrorMiddleware: AsyncMiddleware {
    /// Creates a new `ProblemErrorMiddleware`.
    public init() {}

    /// Forwards the request downstream and converts any thrown error into a
    /// `application/problem+json` response.
    ///
    /// - Parameters:
    ///   - request: The incoming request; used both to invoke the downstream
    ///     responder and, on failure, to access the logger and the original
    ///     HTTP method when shaping the error response.
    ///   - next: The responder whose errors should be translated into problem
    ///     detail responses.
    /// - Returns: The response produced by `next` on success, or a problem
    ///   detail response describing the error on failure. This method does
    ///   not rethrow; errors are always materialized as responses.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return makeResponse(for: error, request: request)
        }
    }

    private func makeResponse(for error: any Error, request: Request) -> Response {
        let problem: ProblemDetails
        switch error {
        case let p as ProblemDetails:
            problem = p
        case let abort as any AbortError:
            problem = ProblemDetails(status: abort.status, detail: abort.reason)
        default:
            request.logger.report(error: error)
            problem = ProblemDetails(status: .internalServerError, detail: "internal server error")
        }
        let response = Response(status: problem.status)
        response.headers.replaceOrAdd(name: .contentType, value: "application/problem+json")
        response.headers.replaceOrAdd(name: .contentLanguage, value: "en")
        response.headers.replaceOrAdd(name: "Content-Version", value: "1")
        do {
            let data = try JSONEncoder().encode(problem)
            response.body = .init(data: data)
        } catch {
            response.body = .init(string: "{\"status\":\(problem.status.code),\"detail\":\"internal server error\"}")
        }
        if request.method == .HEAD {
            response.body = .empty
        }
        return response
    }
}
