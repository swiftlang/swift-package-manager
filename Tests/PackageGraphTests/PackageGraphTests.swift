/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageGraph
import PackageDescription
import PackageLoading
import PackageModel

private let v1: Version = "1.0.0"

class PackageGraphTests: XCTestCase {

    func testBasic() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/source.swift",
            "/Foo/Tests/FooTests/source.swift",
            "/Bar/source.swift",
            "/Bar/Tests/BarTests/source.swift"
        )

        let g = try loadMockPackageGraph([
            "/Foo": Package(name: "Foo"),
            "/Bar": Package(name: "Bar", dependencies: [.Package(url: "/Foo", majorVersion: 1)]),
        ], root: "/Bar", in: fs)

        PackageGraphTester(g) { result in
            result.check(packages: "Bar", "Foo")
            result.check(modules: "Bar", "Foo")
            result.check(testModules: "BarTests")
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
            result.check(testModules: "BarTests")
        }
    }

    static var allTests = [
        ("testBasic", testBasic),
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
        XCTAssertEqual(graph.packages.map {$0.name}, packages, file: file, line: line)
    }

    func check(modules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.packages.flatMap {$0.modules.map {$0.name} }, modules, file: file, line: line)
    }

    func check(testModules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.packages.flatMap {$0.testModules.map {$0.name} }, testModules, file: file, line: line)
    }
}

private func loadMockPackageGraph(_ packageMap: [String: PackageDescription.Package], root: String, in fs: FileSystem) throws -> PackageGraph {
    var externalManifests = [Manifest]()
    var rootManifest: Manifest!
    for (url, package) in packageMap {
        let manifest = Manifest(
            path: AbsolutePath(url).appending(component: Manifest.filename),
            url: url,
            package: package,
            products: [],
            version: v1
        )
        if url == root {
            rootManifest = manifest
        } else {
            externalManifests.append(manifest)
        }
    }
    return try PackageGraphLoader().load(rootManifest: rootManifest, externalManifests: externalManifests, fileSystem: fs)
}
