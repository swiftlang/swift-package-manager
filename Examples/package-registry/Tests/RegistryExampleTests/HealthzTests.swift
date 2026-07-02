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

@Suite("Healthz")
struct HealthzTests {
    @Test func `GET /healthz returns 200`() async throws {
        try await withRegistryApp { app in
            try await app.testing().test(.GET, "/healthz") { res async in
                #expect(res.status == .ok)
            }
        }
    }
}