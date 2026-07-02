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

@Suite("Availability")
struct AvailabilityTests {
    @Test func `GET availability returns an empty 200`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.GET, "/availability") { res async in
                #expect(res.status == .ok)
                #expect(res.body.readableBytes == 0)
            }
        }
    }

    @Test func `GET availability succeeds with the registry Accept header`() async throws {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .accept, value: "application/vnd.swift.registry.v1+json")
        try await withRegistryApp { app in
            try await app.testing().test(.GET, "/availability", headers: headers) { res async in
                #expect(res.status == .ok)
            }
        }
    }
}