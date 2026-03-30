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

internal struct SBOMDependencies: Codable, Equatable {
    internal let components: [SBOMComponent]
    internal let relationships: [SBOMRelationship]?

    internal init(
        components: [SBOMComponent],
        relationships: [SBOMRelationship]? = nil
    ) {
        self.components = components
        self.relationships = relationships
    }
}
