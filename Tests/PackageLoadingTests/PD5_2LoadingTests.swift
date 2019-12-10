/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import SPMTestSupport
import PackageModel
import PackageLoading

class PackageDescription5_2LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_2
    }

    func testMissingTargetProductDependencyPackage() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [],
                dependencies: [
                    .package(url: "/foo1", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: [.product(name: "product")]),
                ]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidManifestFormat(let error, diagnosticFile: _) {
            XCTAssert(error.contains("error: \'product(name:package:)\' is unavailable: the 'package' argument is mandatory as of tools version 5.2"))
        }
    }

    func testPackageName() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [],
                dependencies: [
                    .package(name: "Foo", url: "/foo1", from: "1.0.0"),
                    .package(name: "Foo2", path: "/foo2"),
                    .package(name: "Foo3", url: "/foo3", .upToNextMajor(from: "1.0.0")),
                    .package(name: "Foo4", url: "/foo4", "1.0.0"..<"2.0.0"),
                    .package(name: "Foo5", url: "/foo5", "1.0.0"..."2.0.0"),
                    .package(url: "/bar", from: "1.0.0"),
                    .package(url: "https://github.com/foo/Bar2.git/", from: "1.0.0"),
                    .package(url: "https://github.com/foo/Baz.git", from: "1.0.0"),
                    .package(url: "https://github.com/apple/swift", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: [.product(name: "product", package: "Foo")]),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")
            XCTAssertEqual(manifest.dependencies, [
                .init(name: "Foo", url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")),
                .init(name: "Foo2", url: "/foo2", requirement: .localPackage),
                .init(name: "Foo3", url: "/foo3", requirement: .upToNextMajor(from: "1.0.0")),
                .init(name: "Foo4", url: "/foo4", requirement: .range("1.0.0"..<"2.0.0")),
                .init(name: "Foo5", url: "/foo5", requirement: .range("1.0.0"..<"2.0.1")),
                .init(name: "bar", url: "/bar", requirement: .upToNextMajor(from: "1.0.0")),
                .init(name: "Bar2", url: "https://github.com/foo/Bar2.git/", requirement: .upToNextMajor(from: "1.0.0")),
                .init(name: "Baz", url: "https://github.com/foo/Baz.git", requirement: .upToNextMajor(from: "1.0.0")),
                .init(name: "swift", url: "https://github.com/apple/swift", requirement: .upToNextMajor(from: "1.0.0")),
            ])
        }
    }

    func testTargetDependencyProductInvalidPackage() throws {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Trivial",
                    products: [],
                    dependencies: [
                        .package(name: "Foo", url: "/foo1", from: "1.0.0"),
                    ],
                    targets: [
                        .target(
                            name: "foo",
                            dependencies: [.product(name: "product", package: "foo1")]),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.targetDependencyUnknownPackage(let targetName, let packageName) {
            XCTAssertEqual(targetName, "foo")
            XCTAssertEqual(packageName, "foo1")
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Trivial",
                    products: [],
                    dependencies: [
                        .package(name: "Foo", url: "/foo1", from: "1.0.0"),
                    ],
                    targets: [
                        .target(
                            name: "foo",
                            dependencies: ["bar"]),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.targetDependencyUnknownPackage(let targetName, let packageName) {
            XCTAssertEqual(targetName, "foo")
            XCTAssertEqual(packageName, "bar")
        }
    }

    func testTargetDependencyReference() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [],
                dependencies: [
                    .package(name: "Foobar", url: "/foobar", from: "1.0.0"),
                    .package(name: "Barfoo", url: "/barfoo", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: [.product(name: "Something", package: "Foobar"), "Barfoo"]),
                    .target(
                        name: "bar",
                        dependencies: ["foo"]),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            let dependencies = Dictionary(uniqueKeysWithValues: manifest.dependencies.map({ ($0.name, $0) }))
            let dependencyFoobar = dependencies["Foobar"]!
            let dependencyBarfoo = dependencies["Barfoo"]!
            let targets = Dictionary(uniqueKeysWithValues: manifest.targets.map({ ($0.name, $0) }))
            let targetFoo = targets["foo"]!
            let targetBar = targets["bar"]!
            XCTAssertEqual(manifest.packageDependency(referencedBy: targetFoo.dependencies[0]), dependencyFoobar)
            XCTAssertEqual(manifest.packageDependency(referencedBy: targetFoo.dependencies[1]), dependencyBarfoo)
            XCTAssertEqual(manifest.packageDependency(referencedBy: targetBar.dependencies[0]), nil)
        }
    }
}
