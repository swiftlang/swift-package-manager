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

internal struct SPDXSBOM: Codable, Equatable {
    internal let id: String
    internal let type: SPDXType
    internal let creationInfoID: String
    internal let profileConformance: [String]
    internal let rootElementIDs: [String]

    internal init(
        id: String,
        type: SPDXType,
        creationInfoID: String,
        profileConformance: [String],
        rootElementIDs: [String]
    ) {
        self.id = id
        self.type = type
        self.creationInfoID = creationInfoID
        self.profileConformance = profileConformance
        self.rootElementIDs = rootElementIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id = "spdxId"
        case type
        case creationInfoID = "creationInfo"
        case profileConformance
        case rootElementIDs = "rootElement"
    }
}
