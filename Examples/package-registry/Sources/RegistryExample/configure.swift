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

public func configure(_ app: Application) async throws {
    app.middleware = Middlewares()
    app.middleware.use(ProblemErrorMiddleware())
    app.middleware.use(ContentVersionMiddleware())
    app.middleware.use(HeadMethodMiddleware())
    app.middleware.use(AcceptVersionMiddleware())

    try configureTLS(app)

    let store = app.registryStore
    AvailabilityRoutes().register(app)
    IdentifiersRoutes(store: store).register(app)
    PublishRoutes(publisher: ReleasePublisher(store: store)).register(app)
    MetadataRoutes(store: store).register(app)

    let userStore = app.userStore
    UserRoutes(registrar: UserRegistrar(store: userStore)).register(app)
    LoginRoutes(authenticator: UserAuthenticator(store: userStore)).register(app)
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
