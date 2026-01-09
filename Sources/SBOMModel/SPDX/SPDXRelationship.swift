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

internal struct SPDXRelationship: Codable, Equatable {
    internal enum Category: String, Codable, Equatable {
        case describes
        case dependsOn
        case hasOptionalDependency
        case hasTest
        case generates
        case hasDeclaredLicense
    }

    internal let id: String
    internal let type: SPDXType
    internal let category: Category
    internal let creationInfoID: String
    internal let parentID: String
    internal let childrenID: [String]

    internal init(
        id: String,
        type: SPDXType,
        category: Category,
        creationInfoID: String,
        parentID: String,
        childrenID: [String]
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.creationInfoID = creationInfoID
        self.parentID = parentID
        self.childrenID = childrenID
    }

    private enum CodingKeys: String, CodingKey {
        case id = "spdxId"
        case type
        case category = "relationshipType"
        case creationInfoID = "creationInfo"
        case parentID = "from"
        case childrenID = "to"
    }
}
