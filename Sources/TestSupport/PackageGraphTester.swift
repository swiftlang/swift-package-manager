/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import PackageModel
import PackageGraph

public func PackageGraphTester(_ graph: PackageGraph, _ result: (PackageGraphResult) -> Void) {
    result(PackageGraphResult(graph))
}

public final class PackageGraphResult {
    public let graph: PackageGraph

    public init(_ graph: PackageGraph) {
        self.graph = graph
    }

    public func check(roots: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.rootPackages.map{$0.name}.sorted(), roots.sorted(), file: file, line: line)
    }

    public func check(packages: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.packages.map {$0.name}.sorted(), packages.sorted(), file: file, line: line)
    }

    public func check(targets: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            graph.allTargets
                .filter{ $0.type != .test }
                .map{ $0.name }
                .sorted(), targets.sorted(), file: file, line: line)
    }

    public func check(testModules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            graph.allTargets
                .filter{ $0.type == .test }
                .map{ $0.name }
                .sorted(), testModules.sorted(), file: file, line: line)
    }

    public func find(target: String) -> ResolvedTarget? {
        return graph.allTargets.first(where: { $0.name == target })
    }

    public func check(dependencies: String..., target name: String, file: StaticString = #file, line: UInt = #line) {
        guard let target = find(target: name) else {
            return XCTFail("Module \(name) not found", file: file, line: line)
        }
        XCTAssertEqual(dependencies.sorted(), target.dependencies.map{$0.name}.sorted(), file: file, line: line)
    }
}

extension ResolvedTarget.Dependency {
    public var name: String {
        switch self {
        case .target(let target):
            return target.name
        case .product(let product):
            return product.name
        }
    }
}
