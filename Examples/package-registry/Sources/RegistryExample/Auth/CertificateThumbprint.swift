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
import SwiftASN1
import Vapor
import X509

/// Computes the thumbprint of a certificate
/// A thumbprint uniquely identifies a certificate
enum CertificateThumbprint {
    /// Returns the lowercase hex-encoded SHA-256 of `certificate`'s DER
    /// encoding.
    ///
    /// - Parameter certificate: The certificate to digest.
    /// - Returns: The 64-character lowercase hex thumbprint.
    /// - Throws: An `ASN1Error` if the certificate cannot be re-serialized.
    static func of(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return SHA256.hash(data: serializer.serializedBytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
