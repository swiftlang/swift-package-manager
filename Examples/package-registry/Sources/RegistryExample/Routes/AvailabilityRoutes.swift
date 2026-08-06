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
/// The `/availability` endpoint serves as a liveness probe: a `200 OK`
/// indicates the registry is reachable. The response has an empty body;
/// this registry advertises no optional capabilities.
public struct AvailabilityRoutes: Sendable {
    /// Creates a new `AvailabilityRoutes`.
    public init() {}

    /// Registers `GET /availability` on `router`.
    public func register(_ router: any RoutesBuilder) {
        router.get("availability", use: availability)
    }

    @Sendable
    func availability(req: Request) async throws -> Response {
        Response(status: .ok)
    }
}
