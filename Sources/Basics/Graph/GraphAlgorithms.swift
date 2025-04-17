//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct OrderedCollections.OrderedSet

/// Implements a pre-order depth-first search.
///
/// The cycles are handled by skipping cycle points but it should be possible to
/// to extend this in the future to provide a callback for every cycle.
///
/// - Parameters:
///   - nodes: The list of input nodes to sort.
///   - successors: A closure for fetching the successors of a particular node.
///   - onUnique: A callback to indicate the the given node is being processed for the first time.
///   - onDuplicate: A callback to indicate that the node was already processed at least once.
///
/// - Complexity: O(v + e) where (v, e) are the number of vertices and edges
/// reachable from the input nodes via the relation.
public func depthFirstSearch<T: Hashable>(
    _ nodes: [T],
    successors: (T) throws -> [T],
    onUnique: (T) throws -> Void,
    onDuplicate: (T, T) -> Void
) rethrows {
    var stack = OrderedSet<T>()
    var visited = Set<T>()

    for node in nodes {
        precondition(stack.isEmpty)
        stack.append(node)

        while !stack.isEmpty {
            let curr = stack.removeLast()

            let visitResult = visited.insert(curr)
            if visitResult.inserted {
                try onUnique(curr)
            } else {
                onDuplicate(visitResult.memberAfterInsert, curr)
                continue
            }

            for succ in try successors(curr) {
                stack.append(succ)
            }
        }
    }
}

public func depthFirstSearch<T: Hashable>(
    _ nodes: [T],
    successors: (T) async throws -> [T],
    onUnique: (T) async throws -> Void,
    onDuplicate: (T, T) async -> Void
) async rethrows {
    var stack = OrderedSet<T>()
    var visited = Set<T>()

    for node in nodes {
        precondition(stack.isEmpty)
        stack.append(node)

        while !stack.isEmpty {
            let curr = stack.removeLast()

            let visitResult = visited.insert(curr)
            if visitResult.inserted {
                try await onUnique(curr)
            } else {
                await onDuplicate(visitResult.memberAfterInsert, curr)
                continue
            }

            for succ in try await successors(curr) {
                stack.append(succ)
            }
        }
    }
}

private struct TraversalNode<T: Hashable>: Hashable {
    let parent: T?
    let curr: T
}

/// Implements a pre-order depth-first search that traverses the whole graph and
/// doesn't distinguish between unique and duplicate nodes. The method expects
/// the graph to be acyclic but doesn't check that.
///
/// - Parameters:
///   - nodes: The list of input nodes to sort.
///   - successors: A closure for fetching the successors of a particular node.
///   - onNext: A callback to indicate the node currently being processed
///             including its parent (if any) and its depth.
///
/// - Complexity: O(v + e) where (v, e) are the number of vertices and edges
/// reachable from the input nodes via the relation.
public func depthFirstSearch<T: Hashable>(
    _ nodes: [T],
    successors: (T) throws -> [T],
    onNext: (T, _ parent: T?) throws -> Void
) rethrows {
    var stack = OrderedSet<TraversalNode<T>>()

    for node in nodes {
        precondition(stack.isEmpty)
        stack.append(TraversalNode(parent: nil, curr: node))

        while !stack.isEmpty {
            let node = stack.removeLast()

            try onNext(node.curr, node.parent)

            for succ in try successors(node.curr) {
                stack.append(
                    TraversalNode(
                        parent: node.curr,
                        curr: succ
                    )
                )
            }
        }
    }
}

/// Implements a pre-order depth-first search that traverses the whole graph and
/// doesn't distinguish between unique and duplicate nodes. The visitor can abort
/// a path as needed to prune the tree.
/// The method expects the graph to be acyclic but doesn't check that.
///
/// - Parameters:
///   - nodes: The list of input nodes to sort.
///   - successors: A closure for fetching the successors of a particular node.
///   - onNext: A callback to indicate the node currently being processed
///             including its parent (if any) and its depth. Returns whether to
///             continue down the current path.
///
/// - Complexity: O(v + e) where (v, e) are the number of vertices and edges
/// reachable from the input nodes via the relation.
public enum DepthFirstContinue {
    case `continue`
    case abort
}

public func depthFirstSearch<T: Hashable>(
    _ nodes: [T],
    successors: (T) throws -> [T],
    visitNext: (T, _ parent: T?) throws -> DepthFirstContinue
) rethrows {
    var stack = OrderedSet<TraversalNode<T>>()

    for node in nodes {
        precondition(stack.isEmpty)
        stack.append(TraversalNode(parent: nil, curr: node))

        while !stack.isEmpty {
            let node = stack.removeLast()

            if try visitNext(node.curr, node.parent) == .continue {
                for succ in try successors(node.curr) {
                    stack.append(
                        TraversalNode(
                            parent: node.curr,
                            curr: succ
                        )
                    )
                }
            }
        }
    }
}
