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

/// Compute the transitive closure of an input node set.
///
/// NOTE: The relation is *not* assumed to be reflexive; i.e. the result will
/// not automatically include `nodes` unless present in the relation defined by
/// `successors`.
public func transitiveClosure<T: Hashable>(
    _ nodes: [T], successors: (T) throws -> [T]
) rethrows -> Set<T> {
    var result = Set<T>()

    // The queue of items to recursively visit.
    //
    // We add items post-collation to avoid unnecessary queue operations.
    var queue = nodes
    while let node = queue.popLast() {
        for succ in try successors(node) {
            if result.insert(succ).inserted {
                queue.append(succ)
            }
        }
    }

    return result
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
    _ nodes: [T], successors: (T) throws -> [T]
) throws -> [T] {
    // Implements a topological sort via recursion and reverse postorder DFS.
    func visit(_ node: T,
               _ stack: inout OrderedSet<T>, _ visited: inout Set<T>, _ result: inout [T],
               _ successors: (T) throws -> [T]) throws {
        // Mark this node as visited -- we are done if it already was.
        if !visited.insert(node).inserted {
            return
        }

        // Otherwise, visit each adjacent node.
        for succ in try successors(node) {
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

    // FIXME: This should use a stack not recursion.
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

/// Finds the first cycle encountered in a graph.
///
/// This method uses DFS to look for a cycle and immediately returns when a
/// cycle is encounted.
///
/// - Parameters:
///   - nodes: The list of input nodes to sort.
///   - successors: A closure for fetching the successors of a particular node.
///
/// - Returns: nil if a cycle is not found or a tuple with the path to the start of the cycle and the cycle itself.
public func findCycle<T: Hashable>(
    _ nodes: [T], successors: (T) throws -> [T]
) rethrows -> (path: [T], cycle: [T])? {
    // Ordered set to hold the current traversed path.
    var path = OrderedSet<T>()

    // Function to visit nodes recursively.
    // FIXME: Convert to stack.
    func visit(_ node: T, _ successors: (T) throws -> [T]) rethrows -> (path: [T], cycle: [T])? {
        // If this node is already in the current path then we have found a cycle.
        if !path.append(node) {
            let index = path.index(of: node)!
            return (Array(path[path.startIndex..<index]), Array(path[index..<path.endIndex]))
        }

        for succ in try successors(node) {
            if let cycle = try visit(succ, successors) {
                return cycle
            }
        }
        // No cycle found for this node, remove it from the path.
        let item = path.removeLast()
        assert(item == node)
        return nil
    }

    for node in nodes {
        if let cycle = try visit(node, successors) {
            return cycle
        }
    }
    // Couldn't find any cycle in the graph.
    return nil
}
