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
import Foundation
import Vapor
@testable import RegistryExample

@Suite("TLS configuration")
struct ConfigureTLSTests {
    @Test func `missing cert + key files leave TLS unconfigured`() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try configureTLS(
            app,
            certPath: "/nonexistent/cert.pem",
            keyPath: "/nonexistent/key.pem"
        )
        #expect(app.http.server.configuration.tlsConfiguration == nil)
    }

    @Test func `valid cert + key enables TLS on localhost:8000`() async throws {
        let (certPath, keyPath, cleanup) = try generateSelfSignedCert()
        defer { cleanup() }

        let app = try await Application.make(.testing)
        app.logger.logLevel = .warning
        defer { Task { try? await app.asyncShutdown() } }

        try configureTLS(app, certPath: certPath, keyPath: keyPath)

        #expect(app.http.server.configuration.tlsConfiguration != nil)
        #expect(app.http.server.configuration.hostname == "localhost")
        #expect(app.http.server.configuration.port == 8000)
        #expect(app.http.server.configuration.tlsConfiguration?.minimumTLSVersion == .tlsv12)
    }

    @Test func `malformed cert throws`() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("registry-tls-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let certPath = tmpDir.appendingPathComponent("cert.pem").path
        let keyPath = tmpDir.appendingPathComponent("key.pem").path
        try Data("not a real PEM".utf8).write(to: URL(fileURLWithPath: certPath))
        try Data("not a real PEM".utf8).write(to: URL(fileURLWithPath: keyPath))

        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        #expect(throws: (any Error).self) {
            try configureTLS(app, certPath: certPath, keyPath: keyPath)
        }
    }
}

private func generateSelfSignedCert() throws -> (certPath: String, keyPath: String, cleanup: () -> Void) {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("registry-tls-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let certPath = tmpDir.appendingPathComponent("cert.pem").path
    let keyPath = tmpDir.appendingPathComponent("key.pem").path

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = [
        "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
        "-keyout", keyPath,
        "-out", certPath,
        "-subj", "/CN=localhost",
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        try? FileManager.default.removeItem(at: tmpDir)
        throw TLSCertGenError.opensslFailed(process.terminationStatus)
    }
    return (certPath, keyPath, { try? FileManager.default.removeItem(at: tmpDir) })
}

private enum TLSCertGenError: Error {
    case opensslFailed(Int32)
}