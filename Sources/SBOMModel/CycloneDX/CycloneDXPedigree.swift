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

internal struct CycloneDXAction: Codable, Equatable {
    internal let name: String?
    internal let email: String?

    internal init(
        name: String? = nil,
        email: String? = nil
    ) {
        self.name = name
        self.email = email
    }
}

internal struct CycloneDXCommit: Codable, Equatable {
    internal let uid: String?
    internal let url: String?
    internal let author: CycloneDXAction?
    internal let message: String?

    internal init(
        uid: String? = nil,
        url: String? = nil,
        author: CycloneDXAction? = nil,
        message: String? = nil
    ) {
        self.uid = uid
        self.url = url
        self.author = author
        self.message = message
    }
}

internal struct CycloneDXPedigree: Codable, Equatable {
    internal let commits: [CycloneDXCommit]?

    internal init(commits: [CycloneDXCommit]? = nil) {
        self.commits = commits
    }
}
