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

internal struct SPDXCreationInfo: Codable, Equatable {
    internal let id: String
    internal let type: SPDXType
    internal let specVersion: String?
    internal let createdBy: [String]
    internal let created: String

    internal init(
        id: String,
        type: SPDXType,
        specVersion: String? = nil,
        createdBy: [String],
        created: String
    ) {
        self.id = id
        self.type = type
        self.specVersion = specVersion
        self.createdBy = createdBy
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id = "@id"
        case type
        case specVersion
        case createdBy
        case created
    }
}
