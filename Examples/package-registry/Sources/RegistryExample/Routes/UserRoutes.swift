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

/// Route handler for `POST /users` — unauthenticated account creation.
///
/// This endpoint is a registry-specific convenience (not part of the
/// SE-0292 API surface) that lets a caller create the credential they will
/// then use with `POST /login`. The JSON body is `{ "email", "password"? }`:
/// a non-empty `password` creates a Basic-auth user; omitting `password`
/// (or sending `null`) mints a token user and returns the token once.
///
/// The handler is a thin adapter over ``UserRegistrar``: it decodes and
/// validates the body, then translates ``RegistrationError`` cases into
/// ``ProblemDetails`` responses. On success it returns `201 Created`.
public struct UserRoutes: Sendable {
    let registrar: UserRegistrar

    /// Creates a `UserRoutes` handler backed by the given registrar.
    public init(registrar: UserRegistrar) {
        self.registrar = registrar
    }

    /// Registers `POST /users` on `router`, collecting bodies up to 16 KiB.
    public func register(_ router: any RoutesBuilder) {
        router.on(.POST, "users", body: .collect(maxSize: "16kb"), use: create)
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let body = try decodeBody(req)
        do {
            let result = try await registrar.register(email: body.email, password: body.password)
            let payload = CreateUserResponse(email: result.user.email.value, token: result.token)
            let data = try JSONEncoder.registry.encode(payload)
            let response = Response(status: .created, body: .init(data: data))
            response.headers.replaceOrAdd(name: .contentType, value: "application/json")
            return response
        } catch RegistrationError.invalidEmail {
            // A single response for both a malformed address and an
            // already-registered one. ``UserRegistrar`` collapses the two into
            // one error precisely so this endpoint cannot be used to enumerate
            // which emails have accounts.
            throw ProblemDetails.badRequest("the email address is invalid or unavailable")
        } catch RegistrationError.emptyPassword {
            throw ProblemDetails.badRequest("password must not be empty")
        }
    }

    private func decodeBody(_ req: Request) throws -> CreateUserRequest {
        guard let buffer = req.body.data else {
            throw ProblemDetails.badRequest("request body missing")
        }
        do {
            return try JSONDecoder().decode(CreateUserRequest.self, from: Data(buffer: buffer))
        } catch {
            throw ProblemDetails.badRequest("invalid request body")
        }
    }
}

struct CreateUserRequest: Decodable {
    var email: String
    var password: String?
}

struct CreateUserResponse: Encodable {
    var email: String
    var token: String?
}
