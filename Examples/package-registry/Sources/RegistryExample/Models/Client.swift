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

import X509

/// A client makes authenticated requests on behalf of the user
/// Permissions are scoped to the client, not the user
public struct Client<Auth: AuthenticationMethod>: Sendable, Equatable {
    let user: User
    let auth: Auth
}

public protocol AuthenticationMethod: Sendable, Equatable {
    associatedtype Credentials: Sendable, Hashable
    var credentials: Credentials { get }
}

// MARK: Extensible authentication methods:

struct MutualTLS: AuthenticationMethod, Equatable {
    struct Credentials: Sendable, Hashable, Equatable {
        let rootCertificateAuthority: RootCertificateAuthority
        let id: String
    }

    let credentials: Credentials

    init(rootCertificateAuthority: RootCertificateAuthority, id: String) {
        self.credentials = Credentials(rootCertificateAuthority: rootCertificateAuthority, id: id)
    }

    init(rootCertificateAuthority: RootCertificateAuthority, certificate: Certificate) throws {
        switch rootCertificateAuthority {
        case .none:
            self.init(
                rootCertificateAuthority: rootCertificateAuthority,
                // Use the thumbprint of the self-signed cert to uniquely identify the client
                id: try CertificateThumbprint.of(certificate)
            )
        }
    }
}
