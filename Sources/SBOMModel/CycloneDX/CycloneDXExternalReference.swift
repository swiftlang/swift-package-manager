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

import Foundation

internal struct CycloneDXExternalReference: Codable, Equatable {
    internal enum RefType: String, Codable, Equatable {
        case distribution
    }

    internal let url: URL
    internal let refType: RefType

    internal init(
        url: URL,
        refType: RefType 
    ) {
        self.url = url
        self.refType = refType
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case refType = "type"
    }
}
