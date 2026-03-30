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

import PackageModel

public struct MockProduct {
    public let name: String
    public let modules: [String]
    public let type: ProductType?

    public init(
        name: String,
        modules: [String],
        type: ProductType? = nil
    ) {
        self.name = name
        self.modules = modules
        self.type = type
    }
}
