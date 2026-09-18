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
import X509

public struct ClientCertificateAuthenticator: Sendable {
    let store: UserStore

    public init(store: UserStore) {
        self.store = store
    }

    public func authenticate(certificate: Certificate) async -> RegistryExample.EmailAddress? {
        guard let email = subjectEmail(of: certificate) else { return nil }
        guard await store.user(email: email) != nil else { return nil }
        return email
    }
}
