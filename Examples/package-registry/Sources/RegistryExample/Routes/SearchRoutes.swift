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

import Foundation
import Vapor

/// Route handler for *Search packages* (`GET /search?q={query}`).
///
/// Given a query and optional pagination parameters, the registry responds
/// with the matching packages and the total number of matches. Matching is
/// delegated to ``SearchQuery`` and ``RegistryStore/search(_:limit:offset:)``.
///
/// Responses carry `first`/`prev`/`next`/`last` `Link` headers when the result
/// set spans more than one page, mirroring the pagination links on the §4.1
/// list-releases response.
public struct SearchRoutes: Sendable {
    static let defaultLimit = 20
    static let maxLimit = 100

    let store: RegistryStore

    /// Creates a `SearchRoutes` handler backed by the given store.
    ///
    /// - Parameter store: The registry store to search.
    public init(store: RegistryStore) {
        self.store = store
    }

    /// Registers the `GET /search` route on the supplied router.
    ///
    /// - Parameter router: The Vapor routes builder to attach the handler to.
    public func register(_ router: any RoutesBuilder) {
        router.get("search", use: search)
    }

    @Sendable
    func search(req: Request) async throws -> Response {
        let rawQuery = (try? req.query.get(String.self, at: "q")) ?? ""
        let query = try parseQuery(rawQuery)
        let limit = try parseLimit(req)
        let offset = try parseOffset(req)

        let (hits, total) = await store.search(query, limit: limit, offset: offset)
        let baseURL = req.baseURL
        let results = hits.map { hit in
            SearchResult(
                identity: hit.identifier.description,
                summary: hit.summary,
                latestVersion: hit.latestVersion,
                author: hit.author,
                licenseURL: hit.licenseURL?.absoluteString,
                url: "\(baseURL)/\(hit.identifier.scope)/\(hit.identifier.name)"
            )
        }

        let body = SearchResponse(results: results, total: total, offset: offset, limit: limit)
        let data = try JSONEncoder.registry.encode(body)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .json
        let links = paginationLinks(
            baseURL: baseURL,
            query: rawQuery,
            limit: limit,
            offset: offset,
            total: total
        )
        if !links.isEmpty {
            response.headers.links = links
        }
        return response
    }

    /// Parses the query string, translating a parse failure into a
    /// `400 Bad Request` problem.
    private func parseQuery(_ raw: String) throws -> SearchQuery {
        do {
            return try SearchQuery(parsing: raw)
        } catch SearchQueryError.unknownQualifier(let key) {
            throw ProblemDetails.badRequest("unknown search qualifier '\(key)'")
        }
    }

    /// Parses the `limit` parameter, clamping it into `1...maxLimit`.
    ///
    /// A missing value defaults to ``defaultLimit``; a present but
    /// non-integer value is rejected with `400 Bad Request`.
    private func parseLimit(_ req: Request) throws -> Int {
        guard let raw = try? req.query.get(String.self, at: "limit") else {
            return Self.defaultLimit
        }
        guard let value = Int(raw) else {
            throw ProblemDetails.badRequest("invalid limit parameter")
        }
        return min(max(value, 1), Self.maxLimit)
    }

    /// Parses the `offset` parameter. A missing value defaults to `0`; a
    /// present value must be a non-negative integer.
    private func parseOffset(_ req: Request) throws -> Int {
        guard let raw = try? req.query.get(String.self, at: "offset") else { return 0 }
        guard let value = Int(raw), value >= 0 else {
            throw ProblemDetails.badRequest("invalid offset parameter")
        }
        return value
    }

    /// Builds the `first`/`prev`/`next`/`last` pagination links for a search
    /// response, preserving the query and page size. Returns an empty array
    /// when the results fit on a single page.
    private func paginationLinks(
        baseURL: String,
        query: String,
        limit: Int,
        offset: Int,
        total: Int
    ) -> [HTTPHeaders.Link] {
        guard total > limit else { return [] }
        let lastOffset = ((total - 1) / limit) * limit
        let pageURL = { (offset: Int) -> URL? in
            var components = URLComponents(string: "\(baseURL)/search")
            components?.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            return components?.url
        }
        var specs: [(Int, HTTPHeaders.Link.Relation)] = [(0, .first)]
        if offset > 0 {
            specs.append((max(0, offset - limit), .prev))
        }
        if offset + limit < total {
            specs.append((offset + limit, .next))
        }
        specs.append((lastOffset, .last))
        return specs.compactMap { offset, relation in
            pageURL(offset).map {
                HTTPHeaders.Link(uri: $0.absoluteString, relation: relation, attributes: [:])
            }
        }
    }
}

struct SearchResponse: Encodable {
    var results: [SearchResult]
    var total: Int
    var offset: Int
    var limit: Int
}

struct SearchResult: Encodable {
    var identity: String
    var summary: String?
    var latestVersion: String?
    var author: String?
    var licenseURL: String?
    var url: String?
}
