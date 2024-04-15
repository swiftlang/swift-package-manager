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

struct LinkageGraph<Node> {
    init(nodes: [Node]) {
        self.nodes = nodes
        self.edges = .init(rows: nodes.count, columns: nodes.count)
    }
    
    struct Index {
        fileprivate let value: Int
    }

    private var nodes: [Node]
    private var edges: AdjacencyMatrix

    mutating func addEdge(source: Int, destination: Int) {
        // Adjacency matrix is symmetrical for undirected graphs.
        self.edges[source, destination] = true
        self.edges[destination, source] = true
    }

    // FIXME: linkage graphs are not directed
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
