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

import Testing
import X509
@testable import RegistryExample

@Suite("Client certificate subject email")
struct CertificateSubjectEmailTests {
    @Test func `an emailAddress attribute is read as the identity`() throws {
        let certificate = try clientCertificate(emailAttribute: "mona@example.com")
        #expect(subjectEmail(of: certificate)?.value == "mona@example.com")
    }

    @Test func `a common name holding an email is read as the identity`() throws {
        let certificate = try clientCertificate(commonName: "mona@example.com")
        #expect(subjectEmail(of: certificate)?.value == "mona@example.com")
    }

    @Test func `the emailAddress attribute wins over a differing common name`() throws {
        let certificate = try clientCertificate(
            commonName: "tim@example.com",
            emailAttribute: "mona@example.com"
        )
        #expect(subjectEmail(of: certificate)?.value == "mona@example.com")
    }

    @Test func `a common name that is not an email yields no identity`() throws {
        let certificate = try clientCertificate(commonName: "Mona Lisa Octocat")
        #expect(subjectEmail(of: certificate) == nil)
    }

    @Test func `a subject without a name or email attribute yields no identity`() throws {
        let certificate = try clientCertificate(subject: DistinguishedName {
            OrganizationName("Octocorp")
            CountryName("US")
        })
        #expect(subjectEmail(of: certificate) == nil)
    }

    @Test func `a mixed-case, padded email normalizes like the model does`() throws {
        let certificate = try clientCertificate(emailAttribute: "  Mona@Example.COM ")
        #expect(subjectEmail(of: certificate) == RegistryExample.EmailAddress("mona@example.com"))
    }

    @Test func `an email later in the subject is still found`() throws {
        let certificate = try clientCertificate(subject: DistinguishedName {
            CountryName("US")
            OrganizationName("Octocorp")
            OrganizationalUnitName("Registry")
            X509.EmailAddress("mona@example.com")
        })
        #expect(subjectEmail(of: certificate)?.value == "mona@example.com")
    }

    @Test func `an unparsable emailAddress attribute falls back to the common name`() throws {
        let certificate = try clientCertificate(
            commonName: "mona@example.com",
            emailAttribute: "not-an-email"
        )
        #expect(subjectEmail(of: certificate)?.value == "mona@example.com")
    }
}
