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

internal struct SBOMPerson: Codable, Equatable, Hashable {
    internal let id: SBOMIdentifier
    internal let name: String
    internal let email: String?

    internal init(
        id: SBOMIdentifier,
        name: String,
        email: String?
    ) {
        self.id = id
        self.name = name
        self.email = email
    }
}
