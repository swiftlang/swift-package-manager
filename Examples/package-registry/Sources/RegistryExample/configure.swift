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
import Vapor
import NIOSSL

/// Configures the application's middleware and routes.
///
/// - Parameters:
///   - app: The application to configure.
///   - authEnabled: When `true`, the publish endpoint is gated behind
///     ``RequireLoginMiddleware``, which re-verifies the credentials
///     presented on every publish request. Defaults to `false`, leaving
///     publishing open, matching the server's `--enable-auth` command-line
///     flag.
public func configure(_ app: Application, authEnabled: Bool = false) async throws {
    app.middleware = Middlewares()
    app.middleware.use(ProblemErrorMiddleware())
    app.middleware.use(ContentVersionMiddleware())
    app.middleware.use(HeadMethodMiddleware())
    app.middleware.use(AcceptVersionMiddleware())

    try configureTLS(app)

    let store = app.registryStore
    let userStore = app.userStore
    let authenticator = UserAuthenticator(store: userStore)

    AvailabilityRoutes().register(app)
    IdentifiersRoutes(store: store).register(app)
    let publishRouter: any RoutesBuilder = authEnabled
        ? app.grouped(RequireLoginMiddleware(authenticator: authenticator))
        : app
    PublishRoutes(publisher: ReleasePublisher(store: store)).register(publishRouter)
    MetadataRoutes(store: store).register(app)

    UserRoutes(registrar: UserRegistrar(store: userStore)).register(app)
    LoginRoutes(authenticator: authenticator).register(app)
}

private func configureTLS(_ app: Application) throws {
    try configureTLS(app, certPath: "certs/cert.pem", keyPath: "certs/key.pem")
}

func configureTLS(_ app: Application, certPath: String, keyPath: String) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: certPath),
          fileManager.fileExists(atPath: keyPath)
    else { return }

    let certs = try NIOSSLCertificate.fromPEMFile(certPath).map { NIOSSLCertificateSource.certificate($0) }
    let key = try NIOSSLPrivateKey(file: keyPath, format: .pem)
    var tls = TLSConfiguration.makeServerConfiguration(
        certificateChain: certs,
        privateKey: .privateKey(key)
    )
    tls.minimumTLSVersion = .tlsv12
    app.http.server.configuration.tlsConfiguration = tls
    app.http.server.configuration.hostname = "localhost"
    app.http.server.configuration.port = 8000
    app.logger.info("TLS enabled; listening on https://localhost:8000")
}
