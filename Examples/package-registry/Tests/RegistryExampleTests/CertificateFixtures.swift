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

import struct X509.Certificate

/// A self-signed client certificate with its thumbprint precomputed, so that a
/// test asserting on the thumbprint is not asserting against the same code
/// under test that derives it.
struct TestCertificate: Sendable {
    let pem: String
    /// The SHA-256 of the DER encoding, computed outside the test suite
    /// with `openssl x509 -outform DER | shasum -a 256`.
    let thumbprint: String

    func certificate() throws -> Certificate {
        try Certificate(pemEncoded: pem)
    }
}

let harrysLaptopCertificate = TestCertificate(
    pem: """
        -----BEGIN CERTIFICATE-----
        MIIBgjCCASegAwIBAgIUUMD/N2rrlgXSBvESoeYaXD3L6CUwCgYIKoZIzj0EAwIw
        FTETMBEGA1UEAwwKaWRlbnRpdHktMTAgFw0yNjA3MzExNTA0MDNaGA8yMTI2MDcw
        NzE1MDQwM1owFTETMBEGA1UEAwwKaWRlbnRpdHktMTBZMBMGByqGSM49AgEGCCqG
        SM49AwEHA0IABEM/guBDzyQMsn1dleF9O3T6TkwWyGxtLrOjIxVXfZP9+wLbFnw9
        B0Dmo6C0wPVZXpr+Eq72t5myr7JQixOUJu2jUzBRMB0GA1UdDgQWBBRMaiXyxZUG
        Vm+jJ/NHEdAkKG+JnDAfBgNVHSMEGDAWgBRMaiXyxZUGVm+jJ/NHEdAkKG+JnDAP
        BgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQDSDXL36MHnV1f/0wtx
        LWkeIYSl2h1ESSNUz3FC2XqAtAIhAKE/SiJpo8tHP04igm73t7Cc8PuyhxARgmAY
        FjWWqao8
        -----END CERTIFICATE-----
        """,
    thumbprint: "30ec37382a8099c174b534863d253345b5027f99592db88be0c3629a4a6cb798"
)

let hermionesLaptopCertificate = TestCertificate(
    pem: """
        -----BEGIN CERTIFICATE-----
        MIIBgDCCASegAwIBAgIUTUXy/LZzV3wAZVOsWQ+cYXFTsN0wCgYIKoZIzj0EAwIw
        FTETMBEGA1UEAwwKaWRlbnRpdHktMjAgFw0yNjA3MzExNTA0MDNaGA8yMTI2MDcw
        NzE1MDQwM1owFTETMBEGA1UEAwwKaWRlbnRpdHktMjBZMBMGByqGSM49AgEGCCqG
        SM49AwEHA0IABJ72JAAV2i8A92yi15A89CVEnGiatpyhsE0+Bby1O1NtLTOgTQ+E
        /QUNuItI7VWRlO+FeE6rgPKSN/oL5enBovyjUzBRMB0GA1UdDgQWBBTZkaEVDkpz
        IJh8Su+ou2UgxU8p5jAfBgNVHSMEGDAWgBTZkaEVDkpzIJh8Su+ou2UgxU8p5jAP
        BgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIBNflqAGnVyHhhN0S9TP
        xSPRKhRPLCaL8X+r/J/Sm4ldAiANXlxwIyYq3oPDae5/NhU4dj8rbFZ/b/CAGwQR
        nm+jGw==
        -----END CERTIFICATE-----
        """,
    thumbprint: "2ea1093834f9b724048f1c7a292856271b2244a2f4a44eb6a9aea475925af4f0"
)
