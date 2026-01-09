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

internal struct CycloneDXComponent: Codable, Equatable {
    internal enum Category: String, Codable, Equatable {
        case application
        case framework
        case library
        case file
    }

    internal enum Scope: String, Codable, Equatable {
        case required
        case optional
        case excluded
    }

    internal let type: Category
    internal let bomRef: String
    internal let name: String
    internal let version: String
    internal let scope: Scope
    internal let purl: String
    internal let components: [CycloneDXComponent]?
    internal let pedigree: CycloneDXPedigree?
    internal let properties: [CycloneDXProperty]?
    internal let licenses: [CycloneDXLicense]?

    internal init(
        type: Category,
        bomRef: String,
        name: String,
        version: String,
        scope: Scope,
        purl: String,
        components: [CycloneDXComponent]? = nil,
        pedigree: CycloneDXPedigree? = nil,
        properties: [CycloneDXProperty]? = nil,
        licenses: [CycloneDXLicense]? = nil
    ) {
        self.type = type
        self.bomRef = bomRef
        self.name = name
        self.version = version
        self.scope = scope
        self.purl = purl
        self.components = components
        self.pedigree = pedigree
        self.properties = properties
        self.licenses = licenses
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case bomRef = "bom-ref"
        case name
        case version
        case scope
        case purl
        case components
        case pedigree
        case properties
        case licenses
    }
}
