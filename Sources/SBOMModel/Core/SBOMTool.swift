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

internal struct SBOMTool: Codable, Equatable {
    internal let id: SBOMIdentifier
    internal let name: String
    internal let version: String
    internal let purl: String
    internal let licenses: [SBOMLicense]?

    internal init(
        id: SBOMIdentifier,
        name: String,
        version: String,
        purl: String,
        licenses: [SBOMLicense]? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.purl = purl
        self.licenses = licenses
    }
}
