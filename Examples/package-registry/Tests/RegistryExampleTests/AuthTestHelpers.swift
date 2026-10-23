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

import Crypto
import Foundation
import NIOSSL
import SwiftASN1
import Vapor
import X509

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

func clientCertificate(subject: DistinguishedName) throws -> Certificate {
    let key = Certificate.PrivateKey(P256.Signing.PrivateKey())
    return try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: key.publicKey,
        notValidBefore: Date().addingTimeInterval(-3600),
        notValidAfter: Date().addingTimeInterval(3600),
        issuer: subject,
        subject: subject,
        signatureAlgorithm: .ecdsaWithSHA256,
        extensions: Certificate.Extensions(),
        issuerPrivateKey: key
    )
}

func clientCertificate(commonName: String? = nil, emailAttribute: String? = nil) throws -> Certificate {
    try clientCertificate(subject: DistinguishedName {
        if let commonName {
            CommonName(commonName)
        }
        if let emailAttribute {
            X509.EmailAddress(emailAttribute)
        }
    })
}

func clientCertificate(email: String) throws -> Certificate {
    try clientCertificate(commonName: email, emailAttribute: email)
}

struct CertificateAuthority {
    let certificate: Certificate
    let key: Certificate.PrivateKey
}

func certificateAuthority(commonName: String = "Registry Client CA") throws -> CertificateAuthority {
    let key = Certificate.PrivateKey(P256.Signing.PrivateKey())
    let subject = try DistinguishedName { CommonName(commonName) }
    return CertificateAuthority(
        certificate: try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: key.publicKey,
            notValidBefore: Date().addingTimeInterval(-3600),
            notValidAfter: Date().addingTimeInterval(3600),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            },
            issuerPrivateKey: key
        ),
        key: key
    )
}

func clientCertificate(
    email: String,
    issuedBy authority: CertificateAuthority,
    notValidBefore: Date = Date().addingTimeInterval(-3600),
    notValidAfter: Date = Date().addingTimeInterval(3600)
) throws -> Certificate {
    let key = Certificate.PrivateKey(P256.Signing.PrivateKey())
    return try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: key.publicKey,
        notValidBefore: notValidBefore,
        notValidAfter: notValidAfter,
        issuer: authority.certificate.subject,
        subject: DistinguishedName {
            CommonName(email)
            X509.EmailAddress(email)
        },
        signatureAlgorithm: .ecdsaWithSHA256,
        extensions: Certificate.Extensions(),
        issuerPrivateKey: authority.key
    )
}

func peerChain(_ certificate: Certificate) -> X509.ValidatedCertificateChain {
    X509.ValidatedCertificateChain(uncheckedCertificateChain: [certificate])
}

func nioCertificate(_ certificate: Certificate) throws -> NIOSSLCertificate {
    var serializer = DER.Serializer()
    try serializer.serialize(certificate)
    return try NIOSSLCertificate(bytes: serializer.serializedBytes, format: .der)
}
