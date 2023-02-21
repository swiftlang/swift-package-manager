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

public struct Signature {
    public let data: Data
    public let format: SignatureFormat
    public let signedBy: SigningEntity

    public init(data: Data, format: SignatureFormat) throws {
        self.data = data
        self.format = format

        #if os(macOS)
        var cmsDecoder: CMSDecoder?
        var status = CMSDecoderCreate(&cmsDecoder)
        guard status == errSecSuccess, let cmsDecoder = cmsDecoder else {
            throw SigningError.decodeInitializationFailed("Unable to create CMSDecoder. Error: \(status)")
        }

        status = CMSDecoderUpdateMessage(cmsDecoder, [UInt8](data), data.count)
        guard status == errSecSuccess else {
            throw SigningError
                .decodeInitializationFailed("Unable to update CMSDecoder with signature. Error: \(status)")
        }
        status = CMSDecoderFinalizeMessage(cmsDecoder)
        guard status == errSecSuccess else {
            throw SigningError.decodeInitializationFailed("Failed to set up CMSDecoder. Error: \(status)")
        }

        var certificate: SecCertificate?
        status = CMSDecoderCopySignerCert(cmsDecoder, 0, &certificate)
        guard status == errSecSuccess, let certificate = certificate else {
            throw SigningError.signatureInvalid("Unable to extract signing certificate. Error: \(status)")
        }

        self.signedBy = SigningEntity(certificate: certificate)
        #else
        // TODO: decode `data` by `format`, then construct `signedBy` from signing cert
        fatalError("TO BE IMPLEMENTED")
        #endif
    }
}

public enum SignatureFormat: String {
    case cms_1_0_0 = "cms-1.0.0"
}

// MARK: - SigningEntity is the entity that generated the signature

public struct SigningEntity {
    public let type: SigningEntityType?
    public let name: String?
    public let organizationalUnit: String?
    public let organization: String?

    public var isRecognized: Bool {
        self.type != nil
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
