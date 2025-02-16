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

/// Directed graph that stores edges in [adjacency lists](https://en.wikipedia.org/wiki/Adjacency_list).
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
public struct DirectedGraph<Node> {
    public init(nodes: [Node]) {
        self.nodes = nodes
        self.edges = .init(repeating: [], count: nodes.count)
    }

    public private(set) var nodes: [Node]
    private var edges: [[Int]]

    public mutating func addEdge(source: Int, destination: Int) {
        self.edges[source].append(destination)
    }
    
    /// Checks whether a path via previously created edges between two given nodes exists.
    /// - Parameters:
    ///   - source: `Index` of a node to start traversing edges from.
    ///   - destination: `Index` of a node to which a path could exist via edges from `source`.
    /// - Returns: `true` if a path from `source` to `destination` exists, `false` otherwise.
    @_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
    public func areNodesConnected(source: Int, destination: Int) -> Bool {
        var todo = Deque<Int>([source])
        var done = Set<Int>()

        while !todo.isEmpty {
            let nodeIndex = todo.removeFirst()

            for reachableIndex in self.edges[nodeIndex] {
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
