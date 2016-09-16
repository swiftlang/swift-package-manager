/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

import TestSupport

private func transitiveClosure(_ nodes: [Int], _ successors: [Int: [Int]]) -> [Int] {
    return transitiveClosure(nodes, successors: { successors[$0] ?? [] }).map{$0}.sorted()
}
private func transitiveClosure(_ node: Int, _ successors: [Int: [Int]]) -> [Int] {
    return transitiveClosure([node], successors)
}

private func topologicalSort(_ nodes: [Int], _ successors: [Int: [Int]]) throws -> [Int] {
    return try topologicalSort(nodes, successors: { successors[$0] ?? [] })
}
private func topologicalSort(_ node: Int, _ successors: [Int: [Int]]) throws -> [Int] {
    return try topologicalSort([node], successors)
}

class GraphAlgorithmsTests: XCTestCase {
    func testTransitiveClosure() {
        // A trival graph.
        XCTAssertEqual([2], transitiveClosure(1, [1: [2]]))
        XCTAssertEqual([], transitiveClosure(2, [1: [2]]))
        XCTAssertEqual([2], transitiveClosure([2, 1], [1: [2]]))

        // A diamond.
        let diamond: [Int: [Int]] = [
            1: [3, 2],
            2: [4],
            3: [4]
        ]
        XCTAssertEqual([2, 3, 4], transitiveClosure(1, diamond))
        XCTAssertEqual([4], transitiveClosure([3, 2], diamond))
        XCTAssertEqual([2, 3, 4], transitiveClosure([4, 3, 2, 1], diamond))
        
        // Test cycles.
        XCTAssertEqual([1], transitiveClosure(1, [1: [1]]))
        XCTAssertEqual([1, 2], transitiveClosure(1, [1: [2], 2: [1]]))
    }

    func testTopologicalSort() throws {
        // A trival graph.
        XCTAssertEqual([1, 2], try topologicalSort(1, [1: [2]]))
        XCTAssertEqual([1, 2], try topologicalSort([2, 1], [1: [2]]))

        // A diamond.
        let diamond: [Int: [Int]] = [
            1: [3, 2],
            2: [4],
            3: [4]
        ]
        XCTAssertEqual([1, 2, 3, 4], try topologicalSort(1, diamond))
        XCTAssertEqual([2, 3, 4], try topologicalSort([3, 2], diamond))
        XCTAssertEqual([1, 2, 3, 4], try topologicalSort([4, 3, 2, 1], diamond))

        // Test cycle detection.
        XCTAssertThrows(GraphError.unexpectedCycle) { _ = try topologicalSort(1, [1: [1]]) }
        XCTAssertThrows(GraphError.unexpectedCycle) { _ = try topologicalSort(1, [1: [2], 2: [1]]) }
    }

    static var allTests = [
        ("testTransitiveClosure", testTransitiveClosure),
        ("testTopologicalSort", testTopologicalSort),
    ]
}
