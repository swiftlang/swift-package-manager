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

extension ClientCertificateAuthenticator: AsyncRequestAuthenticator {
    public func authenticate(request: Request) async throws {
        guard request.headers.first(name: .authorization) == nil,
              let certificate = request.peerCertificateChain?.leaf,
              let email = await authenticate(certificate: certificate)
        else { return }
        request.auth.login(AuthenticatedUser(email: email))
    }
}
