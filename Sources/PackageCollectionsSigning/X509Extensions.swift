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

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import SwiftASN1
@_implementationOnly import X509
#else
import SwiftASN1
import X509
#endif

extension Certificate {
    func hasExtension(oid: ASN1ObjectIdentifier) -> Bool {
        self.extensions[oid: oid] != nil
    }
}

extension ASN1ObjectIdentifier.NameAttributes {
    static let userID: ASN1ObjectIdentifier = [0, 9, 2342, 19_200_300, 100, 1, 1]

    // Marker OIDs for ADP certificates
    static let adpSwiftPackageMarker: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 6, 1, 35]
    static let adpSwiftPackageCollectionMarker: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 6, 1, 35]
    static let adpAppleDevelopmentMarkers: [ASN1ObjectIdentifier] = [
        [1, 2, 840, 113_635, 100, 6, 1, 2],
        [1, 2, 840, 113_635, 100, 6, 1, 12],
    ]
    static let adpAppleDistributionMarkers: [ASN1ObjectIdentifier] = [
        [1, 2, 840, 113_635, 100, 6, 1, 4],
        [1, 2, 840, 113_635, 100, 6, 1, 7],
    ]
    static let wwdrIntermediateMarkers: [ASN1ObjectIdentifier] = [
        [1, 2, 840, 113_635, 100, 6, 2, 1],
        [1, 2, 840, 113_635, 100, 6, 2, 15],
    ]
}

extension DistinguishedName {
    var userID: String? {
        self.stringAttribute(oid: ASN1ObjectIdentifier.NameAttributes.userID)
    }

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
                return attribute.value.description
            }
        }
        return nil
    }
}
