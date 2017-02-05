/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
@testable import PackageGraph
import PackageDescription
import PackageModel
import TestSupport
import enum PackageLoading.ModuleError

class PackageGraphTests: XCTestCase {

    func testBasic() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/FooDep/source.swift",
            "/Foo/Tests/FooTests/source.swift",
            "/Bar/source.swift",
            "/Baz/source.swift",
            "/Baz/Tests/BazTests/source.swift"
        )

        let g = try loadMockPackageGraph([
            "/Foo": Package(name: "Foo", targets: [Target(name: "Foo", dependencies: ["FooDep"])]),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
            "/Baz": Package(name: "Baz", dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
        ], root: "/Baz", in: fs)

        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo", "Baz")
            result.check(modules: "Bar", "Foo", "Baz", "FooDep")
            result.check(testModules: "BazTests", "FooTests")
            result.check(dependencies: "FooDep", module: "Foo")
            result.check(dependencies: "Foo", module: "Bar")
            result.check(dependencies: "Bar", module: "Baz")
        }
    }

    func testCycle() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/source.swift",
            "/Bar/source.swift",
            "/Baz/source.swift"
        )

        do {
            _ = try loadMockPackageGraph([
                "/Foo": Package(name: "Foo", dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
                "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Baz", majorVersion: 1)]),
                "/Baz": Package(name: "Baz", dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
            ], root: "/Foo", in: fs)
        } catch PackageGraphError.cycleDetected(let cycle) {
            XCTAssertEqual(cycle.path.map {$0.name}, ["Foo"])
            XCTAssertEqual(cycle.cycle.map {$0.name}.sorted(), ["Bar", "Baz"])
        }
    }

    // Make sure there is no error when we reference Test targets in a package and then
    // use it as a dependency to another package. SR-2353
    func testTestTargetDeclInExternalPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/source.swift",
            "/Foo/Tests/SomeTests/source.swift",
            "/Bar/source.swift",
            "/Bar/Tests/BarTests/source.swift"
        )

        let g = try loadMockPackageGraph([
            "/Foo": Package(name: "Foo", targets: [Target(name: "SomeTests", dependencies: ["Foo"])]),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
        ], root: "/Bar", in: fs)

        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo")
            result.check(modules: "Bar", "Foo")
            result.check(testModules: "BarTests", "SomeTests")
        }
    }

    func testDuplicateModules() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Bar/source.swift",
            "/Bar/source.swift"
        )

        do {
            let g = try loadMockPackageGraph([
                "/Foo": Package(name: "Foo"),
                "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
            ], root: "/Bar", in: fs)
            XCTFail("Unexpected graph \(g)")
        } catch ModuleError.duplicateModule(let module) {
            XCTAssertEqual(module, "Bar")
        }

    }

    static var allTests = [
        ("testBasic", testBasic),
        ("testDuplicateModules", testDuplicateModules),
        ("testCycle", testCycle),
        ("testTestTargetDeclInExternalPackage", testTestTargetDeclInExternalPackage),
    ]
}

private func PackageGraphTester(_ graph: PackageGraph, _ result: (PackageGraphResult) -> Void) {
    result(PackageGraphResult(graph))
}

private class PackageGraphResult {
    let graph: PackageGraph

    init(_ graph: PackageGraph) {
        self.graph = graph
    }

    func check(packages: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.packages.map {$0.name}.sorted(), packages.sorted(), file: file, line: line)
    }

    func check(modules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            graph.packages
                .flatMap{ $0.modules }
                .filter{ $0.type != .test }
                .map{ $0.name }
                .sorted(), modules.sorted(), file: file, line: line)
    }

    func check(testModules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            graph.packages
                .flatMap{ $0.modules }
                .filter{ $0.type == .test }
                .map{ $0.name }
                .sorted(), testModules.sorted(), file: file, line: line)
    }

    func find(module: String) -> ResolvedModule? {
        for pkg in graph.packages {
            if let module = pkg.modules.first(where: { $0.name == module }) {
                return module
            }
        }
        return nil
    }

    func check(dependencies: String..., module name: String, file: StaticString = #file, line: UInt = #line) {
        guard let module = find(module: name) else {
            return XCTFail("Module \(name) not found", file: file, line: line)
        }
        XCTAssertEqual(dependencies.sorted(), module.dependencies.map{$0.name}.sorted(), file: file, line: line)
    }
}

extension ResolvedModule.Dependency {
    var name: String {
        switch self {
        case .target(let target):
            return target.name
        case .product(let product):
            return product.name
        }
    }
}
