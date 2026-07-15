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

import Vapor

extension UserAuthenticator {
    /// - Parameter request: The request whose `Authorization` header is
    ///   verified.
    /// - Returns: The authenticated user's normalized ``EmailAddress``.
    /// - Throws: ``ProblemDetails`` `401 Unauthorized` when the header is
    ///   absent or the credentials are invalid, or `501 Not Implemented`
    ///   when the authentication method is unsupported.
    func authenticate(_ request: Request) async throws -> EmailAddress {
        if let bearer = request.headers.bearerAuthorization {
            guard let email = await authenticate(token: bearer.token) else {
                throw ProblemDetails.unauthorized("Bearer authentication failed: invalid credentials")
            }
            return email
        }

        if let basic = request.headers.basicAuthorization{
            guard let email = await authenticate(email: basic.username, password: basic.password) else {
                throw ProblemDetails.unauthorized("Basic authentication failed: invalid credentials")
            }
            return email
        }

        throw ProblemDetails.unauthorized("Authentication required")
    }
}
