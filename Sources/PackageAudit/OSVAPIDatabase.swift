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

import Basics
import Foundation

import struct TSCBasic.StringError
import struct TSCUtility.Version

/// An `AdvisoryDatabase` backed by an OSV API server (for example `https://api.osv.dev`).
public struct OSVAPIDatabase: AdvisoryDatabase {
    /// The server limits a batch to this many queries.
    static let maxBatchSize = 1000

    private let baseURL: URL
    private let httpClient: HTTPClient

    public init(baseURL: URL, httpClient: HTTPClient) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    public var displayName: String { self.baseURL.absoluteString }
    public var supportsCommitQueries: Bool { true }

    public func advisories(for queries: [AdvisoryQuery]) async throws -> [AdvisoryQuery: [OSVRecord]] {
        var unique: [AdvisoryQuery] = []
        var seen = Set<AdvisoryQuery>()
        for query in queries where seen.insert(query).inserted {
            unique.append(query)
        }

        // Ids per query, in server order.
        var idsByQuery: [AdvisoryQuery: [String]] = [:]
        // Queries still to send, each with the page token of its next page.
        var pending: [(query: AdvisoryQuery, pageToken: String?)] = unique.map { ($0, nil) }

        while !pending.isEmpty {
            var next: [(query: AdvisoryQuery, pageToken: String?)] = []
            for start in stride(from: 0, to: pending.count, by: Self.maxBatchSize) {
                let chunk = Array(pending[start ..< min(start + Self.maxBatchSize, pending.count)])
                let results = try await self.queryBatch(chunk)
                for (entry, result) in zip(chunk, results) {
                    idsByQuery[entry.query, default: []].append(contentsOf: (result.vulns ?? []).map(\.id))
                    if let token = result.nextPageToken, !token.isEmpty {
                        next.append((entry.query, token))
                    }
                }
            }
            pending = next
        }

        var records: [String: OSVRecord] = [:]
        for id in Set(idsByQuery.values.flatMap { $0 }).sorted() {
            records[id] = try await self.fetchRecord(id: id)
        }

        var output: [AdvisoryQuery: [OSVRecord]] = [:]
        for query in unique {
            var seenIDs = Set<String>()
            output[query] = (idsByQuery[query] ?? []).compactMap { id in
                guard seenIDs.insert(id).inserted, let record = records[id], record.withdrawn == nil else {
                    return nil
                }
                return record
            }
        }
        return output
    }

    private func queryBatch(
        _ entries: [(query: AdvisoryQuery, pageToken: String?)]
    ) async throws -> [BatchResult] {
        let body = BatchRequest(queries: entries.map { entry in
            BatchRequest.Query(
                package: .init(ecosystem: OSVRecord.swiftEcosystem, name: entry.query.name),
                version: entry.query.version?.description,
                commit: entry.query.commit,
                pageToken: entry.pageToken
            )
        })
        let url = self.baseURL.appendingPathComponent("v1/querybatch")
        let response: BatchResponse = try await self.send(
            package: entries.count == 1 ? entries[0].query.name : nil
        ) {
            try await self.httpClient.post(
                url,
                body: try JSONEncoder.makeWithDefaults().encode(body),
                headers: Self.headers
            )
        }
        guard response.results.count == entries.count else {
            throw AuditError.advisorySourceFailed(
                source: self.displayName,
                package: nil,
                underlying: "expected \(entries.count) results but received \(response.results.count)"
            )
        }
        return response.results
    }

    private func fetchRecord(id: String) async throws -> OSVRecord {
        let url = self.baseURL.appendingPathComponent("v1/vulns/\(id)")
        return try await self.send(package: nil) {
            try await self.httpClient.get(url, headers: Self.headers)
        }
    }

    private func send<T: Decodable>(
        package: String?,
        _ request: () async throws -> HTTPClientResponse
    ) async throws -> T {
        do {
            let response = try await request()
            guard response.statusCode == 200 else {
                throw StringError("HTTP status \(response.statusCode)")
            }
            guard let value = try response.decodeBody(T.self, using: JSONDecoder.makeWithDefaults()) else {
                throw StringError("empty response body")
            }
            return value
        } catch {
            throw AuditError.advisorySourceFailed(
                source: self.displayName,
                package: package,
                underlying: "\(error)"
            )
        }
    }

    private static var headers: HTTPClientHeaders {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
    }

    private struct BatchRequest: Encodable {
        var queries: [Query]

        struct Query: Encodable {
            var package: Package
            var version: String?
            var commit: String?
            var pageToken: String?

            struct Package: Encodable {
                var ecosystem: String
                var name: String
            }

            enum CodingKeys: String, CodingKey {
                case package, version, commit
                case pageToken = "page_token"
            }
        }
    }

    private struct BatchResponse: Decodable {
        var results: [BatchResult]
    }

    private struct BatchResult: Decodable {
        var vulns: [Vuln]?
        var nextPageToken: String?

        struct Vuln: Decodable {
            var id: String
        }

        enum CodingKeys: String, CodingKey {
            case vulns
            case nextPageToken = "next_page_token"
        }
    }
}
