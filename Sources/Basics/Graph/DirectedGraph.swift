//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct DequeModule.Deque

struct DirectedGraph<Node, Attribute> {
    struct Index {
        fileprivate let value: Int
    }

    private var nodes: [Node]
    private var attributes: [Attribute]
    private var edges: [[Int]]

    mutating func addNode(_ node: Node) -> Index {
        let result = Index(value: self.nodes.count)
        self.nodes.append(node)
        self.edges.append([])

        return result
    }

    mutating func addEdge(source: Index, destination: Index) {
        self.edges[source.value].append(destination.value)
    }

    func areNodesConnected(source: Index, destination: Index) -> Bool {
        var todo = Deque<Int>()
        var done = Set<Int>([source.value])

        while !todo.isEmpty {
            let nodeIndex = todo.removeFirst()

            for reachableIndex in self.edges[nodeIndex] {
                if reachableIndex == destination.value {
                    return true
                } else if !done.contains(reachableIndex) {
                    todo.append(reachableIndex)
                }
            }

            done.insert(nodeIndex)
        }

        return false
    }
}
