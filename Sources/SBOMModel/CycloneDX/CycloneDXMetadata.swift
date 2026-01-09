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

internal struct CycloneDXTools: Codable, Equatable {
    internal let components: [CycloneDXComponent]

    internal init(components: [CycloneDXComponent]) {
        self.components = components
    }
}

internal struct CycloneDXMetadata: Codable, Equatable {
    internal let timestamp: String?
    internal let component: CycloneDXComponent
    internal let tools: CycloneDXTools?

    internal init(
        timestamp: String?,
        component: CycloneDXComponent,
        tools: CycloneDXTools?
    ) {
        self.timestamp = timestamp
        self.component = component
        self.tools = tools
    }
}
