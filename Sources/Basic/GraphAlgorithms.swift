/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum GraphError: Swift.Error {
    /// A cycle was detected in the input.
    case unexpectedCycle
}

/// Perform a topological sort of an graph.
///
/// This function is optimized for use cases where cycles are unexpected, and
/// does not attempt to retain information on the exact nodes in the cycle.
///
/// - Parameters:
///   - nodes: The list of input nodes to sort.
///   - successors: A closure for fetching the successors of a particular node.
///
/// - Returns: A list of the transitive closure of nodes reachable from the
/// inputs, ordered such that every node in the list follows all of its
/// predecessors.
///
/// - Throws: GraphError.unexpectedCycle
///
/// - Complexity: O(v + e) where (v, e) are the number of vertices and edges
/// reachable from the input nodes via the relation.
public func topologicalSort<T: Hashable>(
            _ nodes: [T], successors: @noescape (T) -> [T]) throws -> [T] {
    // Implements a topological sort via recursion and reverse postorder DFS.
    func visit(_ node: T,
               _ stack: inout OrderedSet<T>, _ visited: inout Set<T>, _ result: inout [T],
               _ successors: @noescape (T) -> [T]) throws {
        // Mark this node as visited -- we are done if it already was.
        if !visited.insert(node).inserted {
            return
        }

        // Otherwise, visit each adjacent node.
        for succ in successors(node) {
            guard stack.append(succ) else {
                // If the successor is already in this current stack, we have found a cycle.
                //
                // FIXME: We could easily include information on the cycle we found here.
                throw GraphError.unexpectedCycle
            }
            try visit(succ, &stack, &visited, &result, successors)
            let popped = stack.removeLast()
            assert(popped == succ)
        }

        // Add to the result.
        result.append(node)
    }

    var visited = Set<T>()
    var result = [T]()
    var stack = OrderedSet<T>()
    for node in nodes {
        precondition(stack.isEmpty)
        stack.append(node)
        try visit(node, &stack, &visited, &result, successors)
        let popped = stack.removeLast()
        assert(popped == node)
    }
    
    return result.reversed()
}
