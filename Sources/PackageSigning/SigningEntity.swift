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

#if os(macOS)
import Security
#endif

// MARK: - SigningEntity is the entity that generated the signature

public struct SigningEntity {
    public let type: SigningEntityType?
    public let name: String?
    public let organizationalUnit: String?
    public let organization: String?

    public var isRecognized: Bool {
        self.type != nil
    }

    public init(of signature: Data, signatureFormat: SignatureFormat) throws {
        let provider = signatureFormat.provider
        self = try provider.signingEntity(of: signature)
    }

    #if os(macOS)
    init(certificate: SecCertificate) {
        self.type = certificate.signingEntityType
        self.name = certificate.commonName

        guard let dict = SecCertificateCopyValues(certificate, nil, nil) as? [CFString: Any],
              let subjectDict = dict[kSecOIDX509V1SubjectName] as? [CFString: Any],
              let propValueList = subjectDict[kSecPropertyKeyValue] as? [[String: Any]]
        else {
            self.organizationalUnit = nil
            self.organization = nil
            return
        }

        let props = propValueList.reduce(into: [String: String]()) { result, item in
            if let label = item["label"] as? String, let value = item["value"] as? String {
                result[label] = value
            }
        }

        self.organizationalUnit = props[kSecOIDOrganizationalUnitName as String]
        self.organization = props[kSecOIDOrganizationName as String]
    }
    #endif

    init(certificate: Certificate) {
        // TODO: extract id, name, organization, etc. from cert
        fatalError("TO BE IMPLEMENTED")
    }
}

// MARK: - SigningEntity types that SwiftPM recognizes

public enum SigningEntityType {
    case adp // Apple Developer Program

    static let oid_adpSwiftPackageMarker = "1.2.840.113635.100.6.1.35"
}

#if os(macOS)
extension SecCertificate {
    var signingEntityType: SigningEntityType? {
        guard let dict = SecCertificateCopyValues(
            self,
            [SigningEntityType.oid_adpSwiftPackageMarker as CFString] as CFArray,
            nil
        ) as? [CFString: Any] else {
            return nil
        }
        return dict.isEmpty ? nil : .adp
    }
}
#endif
