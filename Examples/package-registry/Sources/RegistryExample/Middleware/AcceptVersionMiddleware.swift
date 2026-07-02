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

/// Validates the `Accept` header against the package registry's API versioning rules.
///
/// The Swift Package Registry specification (§3.5 *API versioning*) defines the
/// following grammar for a valid registry `Accept` header:
///
/// ```abnf
/// version     = "1"       ; The API version
/// mediatype   = "json" / "zip" / "swift"
/// accept      = "application/vnd.swift.registry" [".v" version] ["+" mediatype]
/// ```
///
/// This middleware enforces that contract:
///
/// - If the client sends an `Accept` header whose version component is not a
///   decimal integer, the request is rejected with `400 Bad Request` and a
///   problem detail of `"invalid API version"`.
/// - If the version is well-formed but does not match the single supported API
///   version (`1`), the request is rejected with `415 Unsupported Media Type`
///   and a problem detail of `"unsupported API version"`.
/// - Entries that do not target the `application/vnd.swift.registry` vendor
///   tree are ignored, allowing standard media types such as `*/*` to pass
///   through.
/// - If no `Accept` header is present, the request is forwarded unchanged, as
///   the specification permits the server to choose an API version in that
///   case.
public struct AcceptVersionMiddleware: AsyncMiddleware {
    private static let supportedVersion = 1
    private static let registryPrefix = "application/vnd.swift.registry"

    /// Creates a new `AcceptVersionMiddleware`.
    public init() {}

    /// Validates the incoming request's `Accept` header and forwards the
    /// request to the next responder when the header is acceptable.
    ///
    /// - Parameters:
    ///   - request: The incoming request, whose `Accept` header (if any) is
    ///     inspected for a `application/vnd.swift.registry.v{n}+{mediatype}`
    ///     entry.
    ///   - next: The responder to invoke once the header has been validated.
    /// - Returns: The response produced by `next`.
    /// - Throws: ``ProblemDetails/badRequest(_:)`` with `"invalid API
    ///   version"` if the version segment is malformed, or
    ///   ``ProblemDetails/unsupportedMediaType(_:)`` with `"unsupported API
    ///   version"` if the requested version is not supported by this server.
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let accept = request.headers.first(name: .accept) {
            try validateAccept(accept)
        }
        return try await next.respond(to: request)
    }

    private func validateAccept(_ accept: String) throws {
        for rawEntry in accept.split(separator: ",") {
            let entry = rawEntry.prefix(while: { $0 != ";" }).trimmingCharacters(in: .whitespaces)
            let lowered = entry.lowercased()
            guard lowered.hasPrefix(Self.registryPrefix) else { continue }
            let remainder = lowered.dropFirst(Self.registryPrefix.count)
            guard remainder.hasPrefix(".v") else { return }
            let afterV = remainder.dropFirst(2)
            let versionChars = afterV.prefix(while: { $0 != "+" })
            guard !versionChars.isEmpty, versionChars.allSatisfy(\.isNumber),
                  let version = Int(versionChars)
            else {
                throw ProblemDetails.badRequest("invalid API version")
            }
            if version != Self.supportedVersion {
                throw ProblemDetails.unsupportedMediaType("unsupported API version")
            }
            return
        }
    }
}
