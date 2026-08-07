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

/// Stamps every outgoing response with the registry's `Content-Version` header.
///
/// The Swift Package Registry specification (§3.5 *API versioning*) requires
/// that:
///
/// > A server MUST set the `Content-Version` header field with the API
/// > version number of the response, unless explicitly stated otherwise.
///
/// A typical response therefore includes:
///
/// ```http
/// HTTP/1.1 200 OK
/// Content-Type: application/json
/// Content-Version: 1
/// ```
///
/// This middleware unconditionally sets `Content-Version: 1` on the response
/// returned from downstream responders, replacing any value that may have
/// been set earlier in the chain. The server currently implements version `1`
/// of the API, which matches the initial version defined by the proposal.
public struct ContentVersionMiddleware: AsyncMiddleware {
    /// Creates a new `ContentVersionMiddleware`.
    public init() {}

    /// Forwards the request to the next responder and stamps `Content-Version: 1`
    /// on the resulting response.
    ///
    /// - Parameters:
    ///   - request: The incoming request, passed through unchanged.
    ///   - next: The responder whose response should be annotated with the
    ///     `Content-Version` header.
    /// - Returns: The downstream response with `Content-Version` set to `1`.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "Content-Version", value: "1")
        return response
    }
}
