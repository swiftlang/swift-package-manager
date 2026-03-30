//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

internal struct SPDXPackage: Codable, Equatable {
    internal enum Purpose: String, Codable, Equatable {
        case application
        case framework
        case library
        case file
    }

    internal let id: String
    internal let type: SPDXType
    internal let purpose: Purpose
    internal let purl: String
    internal let name: String
    internal let version: String
    internal let creationInfoID: String
    internal let description: String?
    internal let summary: String?

    internal init(
        id: String,
        type: SPDXType,
        purpose: Purpose,
        purl: String,
        name: String,
        version: String,
        creationInfoID: String,
        description: String?,
        summary: String?
    ) {
        self.id = id
        self.type = type
        self.purpose = purpose
        self.purl = purl
        self.name = name
        self.version = version
        self.creationInfoID = creationInfoID
        self.description = description
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case id = "spdxId"
        case type
        case purpose = "software_primaryPurpose"
        case purl = "externalUrl"
        case name
        case version = "software_internalVersion"
        case creationInfoID = "creationInfo"
        case description
        case summary
    }
}
