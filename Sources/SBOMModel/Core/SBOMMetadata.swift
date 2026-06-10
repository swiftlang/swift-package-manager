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

internal struct SBOMMetadata: Codable, Equatable {
    internal let timestamp: String?
    internal let creators: [SBOMTool]?

    internal init(
        timestamp: String?,
        creators: [SBOMTool]? = nil
    ) {
        self.timestamp = timestamp
        self.creators = creators
    }
}
