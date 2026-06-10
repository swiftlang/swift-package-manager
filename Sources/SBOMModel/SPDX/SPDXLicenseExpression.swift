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

internal struct SPDXLicenseExpression: Codable, Equatable {
    internal let id: String
    internal let type: SPDXType
    internal let expression: String
    internal let creationInfoID: String

    internal init(
        id: String,
        type: SPDXType,
        expression: String,
        creationInfoID: String,
    ) {
        self.id = id
        self.type = type
        self.expression = expression
        self.creationInfoID = creationInfoID
    }

    private enum CodingKeys: String, CodingKey {
        case id = "spdxId"
        case type
        case expression = "simplelicensing_licenseExpression"
        case creationInfoID = "creationInfo"
    }
}
