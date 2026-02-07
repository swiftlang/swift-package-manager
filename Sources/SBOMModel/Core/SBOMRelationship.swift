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

internal struct SBOMRelationship: Codable, Equatable, Hashable {
    // internal enum Source: String, Codable, Equatable {
    //     case modules // from ModulesGraph
    //     case build // from build dependency graph
    //     case all // appears in all graphs
    // }

    // internal struct Metadata: Codable, Equatable {
    //     let source: Source

    //     internal init(
    //         source: Source,
    //     ) {
    //         self.source = source
    //     }
    // }

    internal let id: SBOMIdentifier
    internal let parentID: SBOMIdentifier
    internal let childrenID: [SBOMIdentifier]

    internal init(
        id: SBOMIdentifier,
        parentID: SBOMIdentifier,
        childrenID: [SBOMIdentifier]
    ) {
        self.id = id
        self.parentID = parentID
        self.childrenID = childrenID
    }
}
