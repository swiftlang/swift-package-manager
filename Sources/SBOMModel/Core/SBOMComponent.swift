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

internal struct SBOMComponent: Codable, Equatable, Hashable {
    internal enum Category: String, Codable, Equatable {
        case application
        case framework
        case library
        case file
    }

    internal enum Scope: String, Codable, Equatable {
        case runtime
        case optional
        case test
    }
    
    internal enum Entity: String, Codable, Equatable {
        case product = "swift-product"
        case package = "swift-package"
    }

    // Specifies the commit or registry entry that is used for the version
    internal struct Version: Codable, Equatable, Hashable {
        internal let revision: String
        internal let commit: SBOMCommit?
        internal let entry: SBOMRegistryEntry?

        internal init(
            revision: String,
            commit: SBOMCommit? = nil,
            entry: SBOMRegistryEntry? = nil
        ) {
            self.revision = revision
            self.commit = commit
            self.entry = entry
        }
    }

    internal let category: Category
    internal let id: SBOMIdentifier
    internal let purl: PURL
    internal let name: String
    internal let version: Version
    internal let originator: SBOMOriginator
    internal let description: String?
    internal let scope: Scope?
    internal let components: [SBOMComponent]?
    internal let entity: Entity

    internal init(
        category: Category,
        id: SBOMIdentifier,
        purl: PURL,
        name: String,
        version: Version,
        originator: SBOMOriginator,
        description: String? = nil,
        scope: Scope?,
        components: [SBOMComponent]? = nil,
        entity: Entity
    ) {
        self.category = category
        self.id = id
        self.purl = purl
        self.name = name
        self.version = version
        self.originator = originator
        self.description = description
        self.scope = scope
        self.components = components
        self.entity = entity
    }
}
