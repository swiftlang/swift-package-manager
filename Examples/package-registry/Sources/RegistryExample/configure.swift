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
///   - authEnabled: When `true` (the default), the publish endpoint is gated
///     behind ``UserAuthenticator`` (an `AsyncRequestAuthenticator`
///     middleware) plus `AuthenticatedUser.guardMiddleware()`, together
///     re-verifying the credentials presented on every publish request.
///     Authentication is on by default so the registry is secure by default;
///     pass `authEnabled: false` (the server's `--disable-auth` flag) to open
///     publishing to unauthenticated clients, e.g. for a quick local demo.
public func configure(_ app: Application, authEnabled: Bool = true) async throws {
    app.middleware = Middlewares()
    app.middleware.use(ProblemErrorMiddleware())
    app.middleware.use(ContentVersionMiddleware())
    app.middleware.use(HeadMethodMiddleware())
    app.middleware.use(AcceptVersionMiddleware())

    try configureTLS(app)

    let store = app.registryStore
    let userStore = app.userStore
    let authenticator = UserAuthenticator(store: userStore)
    let authGroup = app.grouped(authenticator)

    AvailabilityRoutes().register(app)
    IdentifiersRoutes(store: store).register(app)
    let publishRouter: any RoutesBuilder = authEnabled
        ? authGroup.grouped(AuthenticatedUser.guardMiddleware())
        : app
    PublishRoutes(publisher: ReleasePublisher(store: store)).register(publishRouter)
    MetadataRoutes(store: store).register(app)

    UserRoutes(registrar: UserRegistrar(store: userStore)).register(app)
    LoginRoutes().register(authGroup)
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
