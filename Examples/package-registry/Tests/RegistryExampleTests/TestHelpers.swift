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

import Logging
import Vapor
@testable import RegistryExample

func withRegistryApp(
    logLevel: Logger.Level = .warning,
    _ test: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    app.logger.logLevel = logLevel
    do {
        try await configure(app)
        try await app.asyncBoot()
        try await test(app)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}