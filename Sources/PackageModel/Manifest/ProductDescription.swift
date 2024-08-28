//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// The product description
public struct ProductDescription: Hashable, Codable, Sendable {

    /// The name of the product.
    public let name: String

    /// The targets in the product.
    public let targets: [String]

    /// The type of product.
    public let type: ProductType

    public init(
        name: String,
        type: ProductType,
        targets: [String]
    ) throws {
        guard type != .test else {
            throw InternalError("Declaring test products isn't supported: \(name):\(targets)")
        }
        self.name = name
        self.type = type
        self.targets = targets
    }
}
