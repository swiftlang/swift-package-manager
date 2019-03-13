/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
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
/// - Note: The relation is *not* assumed to be reflexive; i.e. the result will
///         not automatically include `nodes` unless present in the relation defined by
///         `successors`.
public func transitiveClosure<T>(
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
    // Stack represented as stackframes consisting from node-successors key-value pairs that
    // are being traversed.
    var stack: OrderedDictionary<T, ArraySlice<T>> = [:]
    // A set of already visited.
    var visited: Set<T> = []
    var result: [T] = []
    
    // Implements a topological sort via iteration and reverse postorder DFS.
    for node in nodes {
        guard visited.insert(node).inserted else { continue }
        stack[node] = try successors(node).dropFirst(0)
        
        // Peek the top of the stack
        while let (node, children) = stack.last {
            // Take the next successor for the given node.
            if let succ = children.first {
                // Drop the first successor from the children list and update the stack frame
                stack[node] = children.dropFirst()
                
                if let _ = stack[succ] {
                    // If the successor is already in this current stack, we have found a cycle.
                    //
                    // FIXME: We could easily include information on the cycle we found here.
                    throw GraphError.unexpectedCycle
                }
                // Mark this node as visited -- we are done if it already was.
                guard visited.insert(succ).inserted else { continue }
                // Push it to the top of the stack
                stack[succ] = try successors(succ).dropFirst(0)
            } else {
                // Pop the node from the stack if all successors traversed.
                stack.removeValue(forKey: node)
                // Add to the result.
                result.append(node)
            }
        }
    }
    // Make sure we popped all of the stack frames.
    assert(stack.isEmpty)
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
    _ nodes: [T],
    successors: (T) throws -> [T]
) rethrows -> (path: [T], cycle: [T])? {
    // Stack represented as stackframes consisting from node-successors key-value pairs that
    // are being traversed.
    var stack: OrderedDictionary<T, ArraySlice<T>> = [:]
    // A set of already visited
    var visited: Set<T> = []
    
    for node in nodes {
        guard visited.insert(node).inserted else { continue }
        stack[node] = try successors(node).dropFirst(0)
        
        // Peek the top of the stack
        while let (node, children) = stack.last {
            // Take the next successor for the given node.
            if let succ = children.first {
                // Drop the first successor from the children list and update the stack frame
                stack[node] = children.dropFirst()
                
                if let _ = stack[succ] {
                    let index = stack.firstIndex { $0.key == succ }!
                    return (
                        Array(stack[stack.startIndex..<index]).map { $0.key },
                        Array(stack[index..<stack.endIndex]).map { $0.key })
                }
                // Mark this node as visited -- we are done if it already was.
                guard visited.insert(succ).inserted else { continue }
                // Push it to the top of the stack
                stack[succ] = try successors(succ).dropFirst(0)
            } else {
                // Pop the node from the stack if all successors traversed.
                stack.removeValue(forKey: node)
            }
        }
    }
    // Make sure we popped all of the stack frames.
    assert(stack.isEmpty)
    // Couldn't find any cycle in the graph.
    return nil
}
