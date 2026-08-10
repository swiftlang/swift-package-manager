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
@testable import RegistryExample

/// A registrar wired to `app`'s user and client stores, so a seeded account is
/// resolvable by the same ``ClientAuthenticator`` the application's routes use.
///
/// - Parameters:
///   - app: The application whose stores the registrar writes to.
///   - tokenGenerator: The source of minted bearer tokens. Pass a fixed
///     generator when a test needs to present the token it seeded.
func userRegistrar(
    for app: Application,
    tokenGenerator: TokenGenerator = .secureRandom
) -> UserRegistrar {
    UserRegistrar(
        store: app.userStore,
        clientRegistrar: ClientRegistrar(store: app.clientStore, tokenGenerator: tokenGenerator)
    )
}

/// A request carrying `headers`, run through `app`'s ``ClientAuthenticator``.
///
/// The returned request holds whichever ``AuthenticatedClient`` the presented
/// credentials verified as — and none at all when they fail — which is the
/// state a route handler or guard sees.
///
/// - Parameters:
///   - app: The application whose client store backs verification.
///   - headers: The headers to present, typically an `Authorization` header.
func authenticatedRequest(for app: Application, headers: HTTPHeaders) async throws -> Request {
    let request = Request(
        application: app,
        method: .POST,
        url: "/login",
        headers: headers,
        on: app.eventLoopGroup.next()
    )
    try await ClientAuthenticator(clientStore: app.clientStore).authenticate(request: request)
    return request
}

func jsonBody(_ raw: String) -> ByteBuffer {
    ByteBuffer(string: raw)
}

func authorizationHeaders(_ value: String) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .authorization, value: value)
    return headers
}

func basicHeaders(email: String, password: String) -> HTTPHeaders {
    authorizationHeaders("Basic \(base64Encode("\(email):\(password)"))")
}

func bearerHeaders(_ token: String) -> HTTPHeaders {
    authorizationHeaders("Bearer \(token)")
}

func base64Encode(_ string: String) -> String {
    Data(string.utf8).base64EncodedString()
}
