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

private import DequeModule

/// Undirected graph that stores edges in an [adjacency matrix](https://en.wikipedia.org/wiki/Adjacency_matrix).
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
public struct UndirectedGraph<Node> {
    public init(nodes: [Node]) {
        self.nodes = nodes
        self.edges = .init(rows: nodes.count, columns: nodes.count)
    }

    private var nodes: [Node]
    private var edges: AdjacencyMatrix

    public mutating func addEdge(source: Int, destination: Int) {
        // Adjacency matrix is symmetrical for undirected graphs.
        self.edges[source, destination] = true
        self.edges[destination, source] = true
    }

    /// Checks whether a connection via previously created edges between two given nodes exists.
    /// - Parameters:
    ///   - source: `Index` of a node to start traversing edges from.
    ///   - destination: `Index` of a node to which a connection could exist via edges from `source`.
    /// - Returns: `true` if a path from `source` to `destination` exists, `false` otherwise.
    public func areNodesConnected(source: Int, destination: Int) -> Bool {
        var todo = Deque<Int>([source])
        var done = Set<Int>()

        while !todo.isEmpty {
            let nodeIndex = todo.removeFirst()

            for reachableIndex in self.edges.nodesAdjacentTo(nodeIndex) {
                if reachableIndex == destination {
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

private extension AdjacencyMatrix {
    func nodesAdjacentTo(_ nodeIndex: Int) -> [Int] {
        var result = [Int]()

        for i in 0..<self.rows where self[i, nodeIndex] {
            result.append(i)
        }

        return result
    }
}
