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
    internal let url: String?
    internal let authors: [SBOMPerson]?
    internal let message: String?

    internal init(
        sha: String,
        repository: String,
        url: String? = nil, // url to the commit
        authors: [SBOMPerson]? = nil,
        message: String? = nil
    ) {
        self.sha = sha
        self.repository = repository
        self.url = url
        self.authors = authors
        self.message = message
    }
}
