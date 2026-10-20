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
import Testing
import Vapor
import VaporTesting
@testable import RegistryExample

@Suite("Search endpoint")
struct SearchRouteTests {
    @Test func `search returns a matching package with its metadata fields`() async throws {
        try await withRegistryApp { app in
            let metadata = #"""
            {"description":"One thing links to another.","author":{"name":"Mona Lisa Octocat"},"licenseURL":"https://example.com/LICENSE"}
            """#
            try await publishHelloWorld(app: app, version: "1.1.1", metadata: metadata)
            try await app.testing().test(.GET, "/search?q=HelloWorld", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == .json)
                #expect(res.headers.first(name: "Content-Version") == "1")
                let body = res.body.string
                #expect(body.contains("\"identity\":\"exampleregistry.HelloWorld\""))
                #expect(body.contains("\"summary\":\"One thing links to another.\""))
                #expect(body.contains("\"latestVersion\":\"1.1.1\""))
                #expect(body.contains("\"author\":\"Mona Lisa Octocat\""))
                #expect(body.contains("\"licenseURL\":\"https://example.com/LICENSE\""))
                #expect(body.contains("/exampleregistry/HelloWorld\""))
                #expect(body.contains("\"total\":1"))
                #expect(body.contains("\"offset\":0"))
                #expect(body.contains("\"limit\":20"))
            }
        }
    }

    @Test func `latestVersion reflects the highest-precedence release including prereleases`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await publishHelloWorld(app: app, version: "2.0.0-beta.1")
            try await app.testing().test(.GET, "/search?q=HelloWorld", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("\"latestVersion\":\"2.0.0-beta.1\""))
            }
        }
    }

    @Test func `empty query returns no results`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(.GET, "/search?q=", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("\"results\":[]"))
                #expect(body.contains("\"total\":0"))
            }
        }
    }

    @Test func `results are ordered by identity and paginate deterministically`() async throws {
        try await withRegistryApp { app in
            try await seedPackages(app: app, names: ["Delta", "Alpha", "Charlie", "Bravo"])
            try await app.testing().test(
                .GET, "/search?q=exampleregistry&limit=2&offset=0", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("\"total\":4"))
                #expect(body.contains("\"limit\":2"))
                #expect(body.contains("exampleregistry.Alpha"))
                #expect(body.contains("exampleregistry.Bravo"))
                #expect(!body.contains("exampleregistry.Charlie"))
                #expect(!body.contains("exampleregistry.Delta"))
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("rel=\"first\""))
                #expect(link.contains("rel=\"next\""))
                #expect(link.contains("rel=\"last\""))
                #expect(!link.contains("rel=\"prev\""))
            }

            try await app.testing().test(
                .GET, "/search?q=exampleregistry&limit=2&offset=2", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("exampleregistry.Charlie"))
                #expect(body.contains("exampleregistry.Delta"))
                #expect(!body.contains("exampleregistry.Alpha"))
                let link = res.headers.first(name: .link) ?? ""
                #expect(link.contains("rel=\"prev\""))
                #expect(link.contains("rel=\"last\""))
                #expect(!link.contains("rel=\"next\""))
            }
        }
    }

    @Test func `single page of results emits no pagination links`() async throws {
        try await withRegistryApp { app in
            try await seedPackages(app: app, names: ["Alpha", "Bravo"])
            try await app.testing().test(.GET, "/search?q=exampleregistry", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: .link) == nil)
            }
        }
    }

    @Test func `out-of-range limit is clamped rather than rejected`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(.GET, "/search?q=HelloWorld&limit=500", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("\"limit\":100"))
            }
            try await app.testing().test(.GET, "/search?q=HelloWorld&limit=0", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("\"limit\":1"))
            }
        }
    }

    @Test func `invalid parameters and unknown qualifiers return 400`() async throws {
        try await withRegistryApp { app in
            let badPaths = [
                "/search?q=x&limit=abc",
                "/search?q=x&offset=-1",
                "/search?q=foo:bar",
            ]
            for path in badPaths {
                try await app.testing().test(.GET, path, headers: acceptJSON) { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }
    }

    @Test func `scope qualifier narrows results to a single scope`() async throws {
        try await withRegistryApp { app in
            try await seedPackages(app: app, names: ["Alpha"], scope: "acme")
            try await seedPackages(app: app, names: ["Bravo"], scope: "other")
            try await app.testing().test(.GET, "/search?q=scope:acme", headers: acceptJSON) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("acme.Alpha"))
                #expect(!body.contains("other.Bravo"))
                #expect(body.contains("\"total\":1"))
            }
        }
    }

    @Test func `author qualifier matches the metadata author name`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(
                app: app,
                version: "1.0.0",
                metadata: #"{"author":{"name":"Mona Lisa Octocat"}}"#
            )
            try await app.testing().test(
                .GET, "/search?q=author:%22Mona%20Lisa%22", headers: acceptJSON
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("exampleregistry.HelloWorld"))
            }
        }
    }
}

func seedPackages(app: Application, names: [String], scope: String = "exampleregistry") async throws {
    for name in names {
        let identifier = try PackageIdentifier(scope: scope, name: name)
        let release = StoredRelease(
            identifier: identifier,
            version: try PackageVersion("1.0.0"),
            sourceArchive: Data(),
            sourceArchiveChecksum: "",
            manifests: [:],
            metadata: nil,
            metadataRaw: nil,
            publishedAt: Date()
        )
        try await app.registryStore.publish(release)
    }
}
