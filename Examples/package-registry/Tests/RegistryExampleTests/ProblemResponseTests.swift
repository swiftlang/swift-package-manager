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

@Suite("Problem+JSON middleware")
struct ProblemResponseTests {
    @Test func `thrown ProblemDetails renders as application/problem+json with Content-Version: 1`() async throws {
        try await withRegistryApp { app in
            app.get("throws-404") { _ -> String in
                throw ProblemDetails(status: .notFound, detail: "release not found")
            }
            try await app.testing().test(.GET, "/throws-404") { res async in
                #expect(res.status == .notFound)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.headers.first(name: "Content-Version") == "1")
                #expect(res.body.string.contains("\"detail\":\"release not found\""))
                #expect(res.body.string.contains("\"status\":404"))
            }
        }
    }

    @Test func `unknown errors render as 500 problem+json`() async throws {
        struct BoomError: Error {}
        try await withRegistryApp { app in
            app.get("boom") { _ -> String in throw BoomError() }
            try await app.testing().test(.GET, "/boom") { res async in
                #expect(res.status == .internalServerError)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.headers.first(name: "Content-Version") == "1")
            }
        }
    }

    @Test func `successful responses also carry Content-Version: 1`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.GET, "/availability") { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "Content-Version") == "1")
            }
        }
    }

    @Test func `unauthorized problems render 401 with a WWW-Authenticate header`() async throws {
        try await withRegistryApp { app in
            app.get("throws-401") { _ -> String in
                throw ProblemDetails.unauthorized("invalid credentials")
            }
            try await app.testing().test(.GET, "/throws-401") { res async in
                #expect(res.status == .unauthorized)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.headers.first(name: .wwwAuthenticate) == "Basic, Bearer")
                #expect(res.body.string.contains("\"status\":401"))
            }
        }
    }

    @Test func `notImplemented problems render 501 problem+json`() async throws {
        try await withRegistryApp { app in
            app.get("throws-501") { _ -> String in
                throw ProblemDetails.notImplemented("unsupported authentication method")
            }
            try await app.testing().test(.GET, "/throws-501") { res async in
                #expect(res.status == .notImplemented)
                #expect(res.headers.first(name: .contentType) == "application/problem+json")
                #expect(res.headers.first(name: .wwwAuthenticate) == nil)
                #expect(res.body.string.contains("\"status\":501"))
            }
        }
    }
}