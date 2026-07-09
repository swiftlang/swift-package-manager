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

/// Route handlers for §4.5 *Lookup package identifiers registered for a
/// URL* (`GET /identifiers?url={url}`).
///
/// Given a URL, the registry responds with the package identifiers
/// associated with that URL. Associations are derived from the
/// ``PackageRelease/repositoryURLs`` field of published release metadata,
/// as described in §4.5.1.
public struct IdentifiersRoutes: Sendable {
    let store: RegistryStore

    /// Creates an `IdentifiersRoutes` handler backed by the given store.
    ///
    /// - Parameter store: The registry store used to resolve URL → package
    ///   identifier mappings.
    public init(store: RegistryStore) {
        self.store = store
    }

    /// Registers the `GET /identifiers` route on the supplied router.
    ///
    /// - Parameter router: The Vapor routes builder to attach the handler
    ///   to.
    public func register(_ router: any RoutesBuilder) {
        router.get("identifiers", use: lookup)
    }

    @Sendable
    func lookup(req: Request) async throws -> Response {
        let url: String
        do {
            url = try req.query.get(String.self, at: "url")
        } catch {
            throw ProblemDetails.badRequest("missing url query parameter")
        }
        let matches = await store.identifiers(matchingURL: url)
        guard !matches.isEmpty else {
            throw ProblemDetails.notFound("no identifiers found for url")
        }
        let body = IdentifiersResponse(identifiers: matches.map { "\($0.scope).\($0.name)" })
        let data = try JSONEncoder().encode(body)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        return response
    }
}

struct IdentifiersResponse: Codable {
    var identifiers: [String]
}
