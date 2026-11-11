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
@testable import PackageAudit
import Testing

import struct TSCBasic.StringError

import struct TSCUtility.Version

@Suite
struct OSVAPIDatabaseTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [HTTPClientRequest] = []
        var requests: [HTTPClientRequest] { self.lock.withLock { self._requests } }
        func add(_ request: HTTPClientRequest) { self.lock.withLock { self._requests.append(request) } }
        var batchBodies: [[String: Any]] {
            self.requests.filter { $0.url.path == "/v1/querybatch" }.map {
                try! JSONSerialization.jsonObject(with: $0.body!) as! [String: Any]
            }
        }
        var vulnPaths: [String] { self.requests.filter { $0.url.path.hasPrefix("/v1/vulns/") }.map(\.url.path) }
    }

    private let base = URL(string: "https://osv.example.com")!

    private func json(_ object: Any) -> HTTPClientResponse {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return .init(statusCode: 200, headers: .init(), body: data)
    }

    private func database(
        _ recorder: Recorder,
        handler: @escaping @Sendable (HTTPClientRequest) throws -> HTTPClientResponse
    ) -> OSVAPIDatabase {
        OSVAPIDatabase(
            baseURL: self.base,
            httpClient: HTTPClient(implementation: { request, _ in
                recorder.add(request)
                return try handler(request)
            })
        )
    }

    private func vulnResponse(for request: HTTPClientRequest) -> HTTPClientResponse {
        let id = request.url.lastPathComponent
        return self.json(["id": id, "summary": "s-\(id)"])
    }

    @Test
    func queryBatchRequestShape() async throws {
        let recorder = Recorder()
        let db = self.database(recorder) { request in
            if request.url.path == "/v1/querybatch" {
                #expect(request.method == .post)
                #expect(request.headers.get("Content-Type").first == "application/json")
                #expect(request.headers.get("Accept").first == "application/json")
                return self.json(["results": [["vulns": [["id": "GHSA-1", "modified": "2025-01-01T00:00:00Z"]]]]])
            }
            #expect(request.method == .get)
            return self.vulnResponse(for: request)
        }
        let query = AdvisoryQuery(name: "github.com/a/b", version: Version(1, 0, 0))
        let result = try await db.advisories(for: [query])

        let body = try #require(recorder.batchBodies.first)
        let expected: [String: Any] = [
            "queries": [["package": ["ecosystem": "SwiftURL", "name": "github.com/a/b"], "version": "1.0.0"]],
        ]
        #expect(NSDictionary(dictionary: body).isEqual(to: expected))
        #expect(recorder.vulnPaths == ["/v1/vulns/GHSA-1"])
        #expect(result[query]?.map(\.id) == ["GHSA-1"])
        #expect(db.supportsCommitQueries)
    }

    @Test
    func commitQueryBody() async throws {
        let recorder = Recorder()
        let db = self.database(recorder) { _ in self.json(["results": [[:]]]) }
        let query = AdvisoryQuery(name: "github.com/a/b", commit: "abc123")
        let result = try await db.advisories(for: [query])
        let queries = try #require(recorder.batchBodies.first?["queries"] as? [[String: Any]])
        #expect(queries.first?["commit"] as? String == "abc123")
        #expect(queries.first?["version"] == nil)
        #expect(result[query] == [])
    }

    @Test
    func batchesAndPaginates() async throws {
        let recorder = Recorder()
        let db = self.database(recorder) { request in
            if request.url.path == "/v1/querybatch" {
                let body = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
                let queries = body["queries"] as! [[String: Any]]
                let results: [[String: Any]] = queries.map { q in
                    let name = (q["package"] as! [String: Any])["name"] as! String
                    if name == "pkg/0" {
                        if q["page_token"] as? String == "tok" {
                            return ["vulns": [["id": "V-page2"]]]
                        }
                        return ["vulns": [["id": "V-page1"]], "next_page_token": "tok"]
                    }
                    return [:]
                }
                return self.json(["results": results])
            }
            return self.vulnResponse(for: request)
        }
        let queries = (0 ..< 1001).map { AdvisoryQuery(name: "pkg/\($0)", version: Version(1, 0, 0)) }
        let result = try await db.advisories(for: queries)

        let sizes = recorder.batchBodies.map { ($0["queries"] as! [Any]).count }
        // 1000 + 1, then one follow-up for the paginated query only.
        #expect(sizes == [1000, 1, 1])
        let followUp = (recorder.batchBodies[2]["queries"] as! [[String: Any]])[0]
        #expect(followUp["page_token"] as? String == "tok")
        #expect((followUp["package"] as! [String: Any])["name"] as? String == "pkg/0")
        #expect(result.count == 1001)
        #expect(result[queries[0]]?.map(\.id) == ["V-page1", "V-page2"])
        #expect(result[queries[1000]] == [])
    }

    @Test
    func deduplicatesVulnFetches() async throws {
        let recorder = Recorder()
        let db = self.database(recorder) { request in
            if request.url.path == "/v1/querybatch" {
                return self.json(["results": [["vulns": [["id": "GHSA-1"]]], ["vulns": [["id": "GHSA-1"]]]]])
            }
            return self.vulnResponse(for: request)
        }
        let a = AdvisoryQuery(name: "x/a", version: Version(1, 0, 0))
        let b = AdvisoryQuery(name: "x/b", version: Version(1, 0, 0))
        let result = try await db.advisories(for: [a, b])
        #expect(recorder.vulnPaths.count == 1)
        #expect(result[a]?.map(\.id) == ["GHSA-1"])
        #expect(result[b]?.map(\.id) == ["GHSA-1"])
    }

    @Test
    func withdrawnRecordsAreDropped() async throws {
        let recorder = Recorder()
        let db = self.database(recorder) { request in
            if request.url.path == "/v1/querybatch" {
                return self.json(["results": [["vulns": [["id": "W-1"]]]]])
            }
            return self.json(["id": "W-1", "withdrawn": "2025-01-01T00:00:00Z"])
        }
        let query = AdvisoryQuery(name: "x/a", version: Version(1, 0, 0))
        #expect(try await db.advisories(for: [query])[query] == [])
    }

    @Test
    func httpErrorThrows() async throws {
        let recorder = Recorder()
        let db = self.database(recorder) { _ in .init(statusCode: 500, headers: .init(), body: nil) }
        let query = AdvisoryQuery(name: "x/a", version: Version(1, 0, 0))
        await #expect {
            try await db.advisories(for: [query])
        } throws: { error in
            guard case AuditError.advisorySourceFailed = error else { return false }
            return true
        }
    }

    @Test
    func factoryRejectsHTTP() throws {
        let client = HTTPClient(implementation: { _, _ in throw StringError("unexpected") })
        #expect {
            try makeAdvisoryDatabase(url: URL(string: "http://osv.example.com")!, httpClient: client, fileSystem: localFileSystem)
        } throws: { error in
            guard case AuditError.unsupportedAdvisoryDatabaseURL = error else { return false }
            return true
        }
        let db = try makeAdvisoryDatabase(url: URL(string: "https://osv.example.com")!, httpClient: client, fileSystem: localFileSystem)
        #expect(db is OSVAPIDatabase)
    }
}
