//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package struct Target {
    /// The name of the target.
    package var name: String

    /// The list of nodes that should be computed to build this target.
    package var nodes: [Node]

    package init(name: String, nodes: [Node]) {
        self.name = name
        self.nodes = nodes
    }
}
