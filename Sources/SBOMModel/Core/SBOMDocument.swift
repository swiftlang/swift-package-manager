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

internal struct SBOMDocument: Codable, Equatable {
    internal let id: SBOMIdentifier
    internal let metadata: SBOMMetadata
    internal let primaryComponent: SBOMComponent
    internal let dependencies: SBOMDependencies
    internal let licenses: [SBOMLicense]?

    internal init(
        id: SBOMIdentifier,
        metadata: SBOMMetadata,
        primaryComponent: SBOMComponent,
        dependencies: SBOMDependencies,
        licenses: [SBOMLicense]? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.primaryComponent = primaryComponent
        self.dependencies = dependencies
        self.licenses = licenses
    }
}
