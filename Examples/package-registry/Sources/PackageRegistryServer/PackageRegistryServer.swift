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

import ArgumentParser
import Vapor
import RegistryExample

@main
struct PackageRegistryServer: ArgumentParser.AsyncParsableCommand {
    static let configuration = ArgumentParser.CommandConfiguration(
        commandName: "PackageRegistryServer",
        abstract: "A reference Swift Package Registry server."
    )

    @ArgumentParser.Flag(
        name: .customLong("enable-auth"),
        help: "Require a logged-in user to publish releases (POST /login first)."
    )
    var enableAuth = false

    func run() async throws {
        var env = try Environment.detect(arguments: CommandLine.arguments.filter { $0 != "--enable-auth" })
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            try await configure(app, authEnabled: enableAuth)
            try await app.execute()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
