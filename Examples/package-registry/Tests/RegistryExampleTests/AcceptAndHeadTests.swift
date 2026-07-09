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

import Testing
import Vapor
import VaporTesting
@testable import RegistryExample

@Suite("Accept header API version handling")
struct AcceptVersionTests {
    @Test func `missing Accept header is accepted`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.GET, "/availability") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `Accept application/vnd.swift.registry.v1+json is accepted`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v1+json")
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `Accept application/vnd.swift.registry (no version) is accepted`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry+json")
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `valid but unsupported API version returns 415 problem+json`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v2+json")
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .unsupportedMediaType)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.body.string.contains("unsupported API version: 2"))
            }
        }
    }

    @Test func `invalid API version returns 400 problem+json`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.vFOO+json")
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .badRequest)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.body.string.contains("invalid API version: foo"))
            }
        }
    }

    @Test func `non-registry Accept media types pass through`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .accept, value: "application/json")
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test func `registry entry is validated even when listed after other media types`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(
                name: .accept,
                value: "*/*, application/vnd.swift.registry.v2+json"
            )
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .unsupportedMediaType)
            }
        }
    }
}

@Suite("HEAD request handling")
struct HeadRequestTests {
    @Test func `HEAD /availability returns 200 with no body`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.HEAD, "/availability") { res async in
                #expect(res.status == .ok)
                #expect(res.body.readableBytes == 0)
                #expect(res.headers.first(name: "Content-Version") == "1")
            }
        }
    }

    @Test func `HEAD on an unknown package returns 404 with empty body`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.HEAD, "/nobody/Ghost") { res async in
                #expect(res.status == .notFound)
                #expect(res.body.readableBytes == 0)
            }
        }
    }

    @Test func `HEAD with unsupported Accept version returns 415 with empty body`() async throws {
        try await withRegistryApp { app in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v2+json")
            try await app.testing().test(.HEAD, "/availability", headers: headers) { res async in
                #expect(res.status == .unsupportedMediaType)
                #expect(res.body.readableBytes == 0)
            }
        }
    }

    @Test func `HEAD on a published release returns 200 with empty body`() async throws {
        try await withRegistryApp { app in
            try await publishHelloWorld(app: app, version: "1.0.0")
            try await app.testing().test(.HEAD, "/exampleregistry/HelloWorld/1.0.0") { res async in
                #expect(res.status == .ok)
                #expect(res.body.readableBytes == 0)
            }
        }
    }
}