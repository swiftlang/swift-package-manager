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

/// Route handler for `GET /availability`.
///
/// The `/availability` endpoint is a liveness probe: a `200 OK` means the
/// registry is reachable. The body advertises the optional capabilities this
/// registry supports, so a client can check whether `search` is available
/// before calling it.
public struct AvailabilityRoutes: Sendable {
    /// Creates a new `AvailabilityRoutes`.
    public init() {}

    /// Registers `GET /availability` on `router`.
    public func register(_ router: any RoutesBuilder) {
        router.get("availability", use: availability)
    }

    @Sendable
    func availability(req: Request) async throws -> Response {
        let body = AvailabilityResponse(capabilities: ["search": Capability()])
        let data = try JSONEncoder.registry.encode(body)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .json
        return response
    }
}

/// The body of a `GET /availability` response, advertising each supported
/// optional capability by name.
struct AvailabilityResponse: Encodable {
    var capabilities: [String: Capability]
}

/// Details of a single advertised capability. Empty for now; a capability's
/// presence in ``AvailabilityResponse/capabilities`` is what signals support.
struct Capability: Encodable {}
