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

internal struct CycloneDXDocument: Codable, Equatable {
    internal let schema: String
    internal let bomFormat: String
    internal let specVersion: String
    internal let serialNumber: String
    internal let version: Int
    internal let metadata: CycloneDXMetadata
    internal let components: [CycloneDXComponent]?
    internal let dependencies: [CycloneDXDependency]?

    internal init(
        schema: String,
        bomFormat: String,
        specVersion: String,
        serialNumber: String,
        version: Int,
        metadata: CycloneDXMetadata,
        components: [CycloneDXComponent]? = nil,
        dependencies: [CycloneDXDependency]? = nil
    ) {
        self.schema = schema
        self.bomFormat = bomFormat
        self.specVersion = specVersion
        self.serialNumber = serialNumber
        self.version = version
        self.metadata = metadata
        self.components = components
        self.dependencies = dependencies
    }

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case bomFormat
        case specVersion
        case serialNumber
        case version
        case metadata
        case components
        case dependencies
    }
}
