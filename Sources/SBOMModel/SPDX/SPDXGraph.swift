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

import Foundation

internal struct SPDXGraphElement: Encodable {
    private let value: any Encodable

    internal init(_ value: some Encodable) {
        self.value = value
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }

    internal func getValue<T>() -> T? {
        self.value as? T
    }
}

internal struct SPDXGraph: Encodable {
    internal let context: String
    internal let graph: [SPDXGraphElement]

    internal init(
        context: String,
        graph: [SPDXGraphElement]
    ) {
        self.context = context
        self.graph = graph
    }

    internal init(
        context: String,
        graph: [any SPDXObject]
    ) {
        self.context = context
        self.graph = graph.map { SPDXGraphElement($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case context = "@context"
        case graph = "@graph"
    }
}
