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
import X509
@testable import RegistryExample

@Suite("Mutual TLS authentication end-to-end")
struct ClientCertificateRouteTests {
    private func seedPasswordUser(_ app: Application, email: String, password: String) async throws {
        _ = try await UserRegistrar(store: app.userStore).register(email: email, password: password)
    }

    private func respond(
        _ app: Application,
        method: HTTPMethod,
        url: URI,
        headers: HTTPHeaders = HTTPHeaders(),
        body: ByteBuffer? = nil,
        certificate: Certificate? = nil
    ) async throws -> Response {
        let request = Request(
            application: app,
            method: method,
            url: url,
            headers: headers,
            collectedBody: body,
            peerCertificateChain: certificate.map(peerChain),
            on: app.eventLoopGroup.next()
        )
        return try await app.responder.respond(to: request).get()
    }

    @Test func `a certificate for a registered user logs in`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .POST, url: "/login",
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .ok)
            #expect(response.body.string?.contains("mona@example.com") == true)
        }
    }

    @Test func `a certificate for an unregistered email is 401`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .POST, url: "/login",
                certificate: try clientCertificate(email: "ghost@example.com")
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test func `an Authorization header wins over a differing certificate`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await seedPasswordUser(app, email: "tim@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .POST, url: "/login",
                headers: basicHeaders(email: "tim@example.com", password: "hunter2"),
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .ok)
            #expect(response.body.string?.contains("tim@example.com") == true)
        }
    }

    @Test func `a certificate alone authorizes publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .PUT, url: "/catalogdev/HelloWorld/1.0.0",
                headers: publishHeaders(),
                body: publishMultipartBody(zip: try makeHelloWorldZip(), metadata: nil),
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .created)
        }
    }

    @Test func `a certificate combined with basic credentials authorizes publishing`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            var headers = publishHeaders()
            headers.replaceOrAdd(name: .authorization, value: "Basic \(base64Encode("mona@example.com:hunter2"))")
            let response = try await respond(
                app, method: .PUT, url: "/catalogdev/HelloWorld/1.0.0",
                headers: headers,
                body: publishMultipartBody(zip: try makeHelloWorldZip(), metadata: nil),
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .created)
        }
    }

    @Test func `an unregistered certificate cannot publish`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .PUT, url: "/catalogdev/HelloWorld/1.0.0",
                headers: publishHeaders(),
                body: publishMultipartBody(zip: try makeHelloWorldZip(), metadata: nil),
                certificate: try clientCertificate(email: "ghost@example.com")
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test func `basic credentials without a certificate still log in`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .POST, url: "/login",
                headers: basicHeaders(email: "mona@example.com", password: "hunter2")
            )
            #expect(response.status == .ok)
            #expect(response.body.string?.contains("mona@example.com") == true)
        }
    }

    @Test func `neither a certificate nor credentials is 401`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(app, method: .POST, url: "/login")
            #expect(response.status == .unauthorized)
            #expect(response.headers.first(name: .wwwAuthenticate) == "Basic, Bearer")
        }
    }

    @Test func `a rejected Authorization header is 401 despite a certificate`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            try await seedPasswordUser(app, email: "tim@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .POST, url: "/login",
                headers: basicHeaders(email: "tim@example.com", password: "wrong"),
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test func `a rejected bearer token cannot publish under a certificate`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            var headers = publishHeaders()
            headers.replaceOrAdd(name: .authorization, value: "Bearer not-a-real-token")
            let response = try await respond(
                app, method: .PUT, url: "/catalogdev/HelloWorld/1.0.0",
                headers: headers,
                body: publishMultipartBody(zip: try makeHelloWorldZip(), metadata: nil),
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test func `an unsupported scheme is still 501 when a certificate is present`() async throws {
        try await withRegistryApp(authEnabled: true) { app in
            try await seedPasswordUser(app, email: "mona@example.com", password: "hunter2")
            let response = try await respond(
                app, method: .POST, url: "/login",
                headers: authorizationHeaders("Digest username=\"mona\""),
                certificate: try clientCertificate(email: "mona@example.com")
            )
            #expect(response.status == .notImplemented)
        }
    }
}
