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

internal struct SBOMOriginator: Codable, Equatable, Hashable {
    internal let commits: [SBOMCommit]?
    internal let entries: [SBOMRegistryEntry]?

    internal init(
        commits: [SBOMCommit]? = nil,
        entries: [SBOMRegistryEntry]? = nil,
    ) {
        self.commits = commits
        self.entries = entries
    }
}
