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

internal struct SBOMIdentifier: Codable, Equatable, Hashable {
    internal let value: String

    internal init(value: String) {
        self.value = value
    }

    internal static func generate() -> SBOMIdentifier {
        SBOMIdentifier(value: "urn:uuid:\(UUID().uuidString.lowercased())")
    }
}
