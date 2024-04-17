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

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import Basics

import XCTest

final class UndirectedGraphTests: XCTestCase {
    func testNodesConnection() {
        var graph = UndirectedGraph(nodes: ["app1", "lib1", "lib2", "app2", "lib3", "app3"])
        graph.addEdge(source: 0, destination: 1)
        graph.addEdge(source: 1, destination: 2)
        XCTAssertTrue(graph.areNodesConnected(source: 0, destination: 2))
        XCTAssertTrue(graph.areNodesConnected(source: 2, destination: 0))

        graph.addEdge(source: 0, destination: 4)
        graph.addEdge(source: 3, destination: 4)
        XCTAssertTrue(graph.areNodesConnected(source: 3, destination: 4))
        XCTAssertTrue(graph.areNodesConnected(source: 4, destination: 3))
        XCTAssertTrue(graph.areNodesConnected(source: 0, destination: 4))
        XCTAssertTrue(graph.areNodesConnected(source: 4, destination: 0))
        XCTAssertTrue(graph.areNodesConnected(source: 1, destination: 4))
        XCTAssertTrue(graph.areNodesConnected(source: 4, destination: 1))

        for i in 0...4 {
            XCTAssertFalse(graph.areNodesConnected(source: i, destination: 5))
            XCTAssertFalse(graph.areNodesConnected(source: 5, destination: i))
        }
    }
}
