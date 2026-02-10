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

internal struct SBOMRegistryEntry: Hashable, Codable, Equatable {
    internal let url: URL?
    internal let scope: String
    internal let name: String
    internal let version: String

    internal init(
        url: URL? = nil,
        scope: String,
        name: String,
        version: String,
    ) {
        self.url = url
        self.scope = scope
        self.name = name
        self.version = version
    }
}
