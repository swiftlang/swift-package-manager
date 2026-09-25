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

import SwiftASN1
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

    /// Gets the email from the email address field in `certificate`
    /// The common name field is used if there is no email field
    private func subjectEmail(of certificate: Certificate) -> RegistryExample.EmailAddress? {
        let attributes = certificate.subject.flatMap { $0 }
        return email(in: attributes, typed: .RDNAttributeType.emailAddress)
            ?? email(in: attributes, typed: .RDNAttributeType.commonName)
    }

    private func email(
        in attributes: [RelativeDistinguishedName.Attribute],
        typed type: ASN1ObjectIdentifier
    ) -> RegistryExample.EmailAddress? {
        attributes
            .lazy
            .filter { $0.type == type }
            .compactMap { String($0.value) }
            .compactMap(RegistryExample.EmailAddress.init)
            .first
    }
}
