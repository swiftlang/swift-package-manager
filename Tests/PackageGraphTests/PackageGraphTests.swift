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

        let engine = DiagnosticsEngine()
        let g = loadMockPackageGraph([
            "/Foo": Package(name: "Foo", targets: [Target(name: "Foo", dependencies: ["FooDep"])]),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
            "/Baz": Package(name: "Baz", dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
        ], root: "/Baz", engine: engine, in: fs)

        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo", "Baz")
            result.check(modules: "Bar", "Foo", "Baz", "FooDep")
            result.check(testModules: "BazTests", "FooTests")
            result.check(dependencies: "FooDep", module: "Foo")
            result.check(dependencies: "Foo", module: "Bar")
            result.check(dependencies: "Bar", module: "Baz")
        }
    }

    func testProductDependencies() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Bar/source.swift"
        )

        let engine = DiagnosticsEngine()
        let g = loadMockPackageGraph4([
            "/Bar": .init(name: "Bar", products: [.Library(name: "Bar", targets: ["Bar"])]),
            "/Foo": .init(
                name: "Foo",
                targets: [.init(name: "Foo", dependencies: ["Bar"])],
                dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
        ], root: "/Foo", engine: engine, in: fs)

        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo")
            result.check(modules: "Bar", "Foo")
            result.check(dependencies: "Bar", module: "Foo")
        }
    }

    func testCycle() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/source.swift",
            "/Bar/source.swift",
            "/Baz/source.swift"
        )

        let engine = DiagnosticsEngine()
        _ = loadMockPackageGraph([
            "/Foo": Package(name: "Foo", dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Baz", majorVersion: 1)]),
            "/Baz": Package(name: "Baz", dependencies: [.Package(url: "/Bar", majorVersion: 1)]),
        ], root: "/Foo", engine: engine, in: fs)

        XCTAssertEqual(engine.diagnostics[0].localizedDescription, "found cyclic dependency declaration: Foo -> Bar -> Baz -> Bar")
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

        let g = loadMockPackageGraph([
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

        let engine = DiagnosticsEngine()
        _ = loadMockPackageGraph([
            "/Foo": Package(name: "Foo"),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
        ], root: "/Bar", engine: engine, in: fs)

        XCTAssertEqual(engine.diagnostics[0].localizedDescription, "multiple modules with the name Bar found fix: modules should have a unique name across dependencies")
    }

    static var allTests = [
        ("testBasic", testBasic),
        ("testDuplicateModules", testDuplicateModules),
        ("testCycle", testCycle),
        ("testProductDependencies", testProductDependencies),
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
