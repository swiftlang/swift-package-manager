//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data

#if canImport(Darwin)
import Security
#endif

import Basics
@_implementationOnly import SwiftASN1
@_implementationOnly import X509

#if canImport(Darwin)
extension Certificate {
    init(secCertificate: SecCertificate) throws {
        let data = SecCertificateCopyData(secCertificate) as Data
        self = try Certificate(derEncoded: Array(data))
    }

    init(secIdentity: SecIdentity) throws {
        var secCertificate: SecCertificate?
        let status = SecIdentityCopyCertificate(secIdentity, &secCertificate)
        guard status == errSecSuccess, let secCertificate = secCertificate else {
            throw StringError("Failed to get certificate from SecIdentity. Error: \(status)")
        }
        self = try Certificate(secCertificate: secCertificate)
    }
}
#endif

extension Certificate {
    func hasExtension(oid: ASN1ObjectIdentifier) -> Bool {
        self.extensions[oid: oid] != nil
    }
}

extension DistinguishedName {
    var commonName: String? {
        self.stringAttribute(oid: ASN1ObjectIdentifier.NameAttributes.commonName)
    }

    var organizationalUnitName: String? {
        self.stringAttribute(oid: ASN1ObjectIdentifier.NameAttributes.organizationalUnitName)
    }

    var organizationName: String? {
        self.stringAttribute(oid: ASN1ObjectIdentifier.NameAttributes.organizationName)
    }

    private func stringAttribute(oid: ASN1ObjectIdentifier) -> String? {
        for relativeDistinguishedName in self {
            for attribute in relativeDistinguishedName where attribute.type == oid {
                if let stringValue = attribute.stringValue {
                    return stringValue
                }
            }
        }
        return nil
    }
}

extension RelativeDistinguishedName.Attribute {
    fileprivate var stringValue: String? {
        let asn1StringBytes: ArraySlice<UInt8>?
        do {
            asn1StringBytes = try ASN1PrintableString(asn1Any: self.value).bytes
        } catch {
            asn1StringBytes = try? ASN1UTF8String(asn1Any: self.value).bytes
        }

        guard let asn1StringBytes = asn1StringBytes,
              let stringValue = String(bytes: asn1StringBytes, encoding: .utf8)
        else {
            return nil
        }
        return stringValue
    }
}
