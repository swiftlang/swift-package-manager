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

internal struct SBOMCommit: Hashable, Codable, Equatable {
    internal let sha: String
    internal let repository: String
    internal let authors: [SBOMPerson]?

    internal init(
        sha: String,
        repository: String,
        authors: [SBOMPerson]? = nil,
    ) {
        self.sha = sha
        self.repository = repository
        self.authors = authors
    }
}
