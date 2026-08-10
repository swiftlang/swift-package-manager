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

public struct MutualTLS: AuthenticationMethod, Equatable {
    public struct Credentials: Sendable, Hashable, Equatable {
        public let rootCertificateAuthority: RootCertificateAuthority
        public let id: String

        public init(rootCertificateAuthority: RootCertificateAuthority, id: String) {
            self.rootCertificateAuthority = rootCertificateAuthority
            self.id = id
        }
    }

    public let credentials: Credentials

    public init(rootCertificateAuthority: RootCertificateAuthority, id: String) {
        self.credentials = Credentials(rootCertificateAuthority: rootCertificateAuthority, id: id)
    }

    public init(rootCertificateAuthority: RootCertificateAuthority, certificate: Certificate) throws {
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

extension AuthMethods.MTLS {
    static func client(
        user: User,
        rootCertificateAuthority: RootCertificateAuthority,
        id: String
    ) -> RegisteredClient<MutualTLS> {
        RegisteredClient(
            user: user,
            auth: MutualTLS(rootCertificateAuthority: rootCertificateAuthority, id: id)
        )
    }

    static func client(
        user: User,
        rootCertificateAuthority: RootCertificateAuthority,
        certificate: Certificate
    ) throws -> RegisteredClient<MutualTLS> {
        RegisteredClient(
            user: user,
            auth: try MutualTLS(
                rootCertificateAuthority: rootCertificateAuthority,
                certificate: certificate
            )
        )
    }
}
