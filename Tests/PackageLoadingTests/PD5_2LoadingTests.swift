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
            XCTAssertEqual(manifest.dependencies[0].name, "Foo")
            XCTAssertEqual(manifest.dependencies[1].name, "Foo2")
            XCTAssertEqual(manifest.dependencies[2].name, "Foo3")
            XCTAssertEqual(manifest.dependencies[3].name, "Foo4")
            XCTAssertEqual(manifest.dependencies[4].name, "Foo5")
            XCTAssertEqual(manifest.dependencies[5].name, "bar")
            XCTAssertEqual(manifest.dependencies[6].name, "Bar2")
            XCTAssertEqual(manifest.dependencies[7].name, "Baz")
            XCTAssertEqual(manifest.dependencies[8].name, "swift")
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
                            name: "Target1",
                            dependencies: [.product(name: "product", package: "foo1")]),
                        .target(
                            name: "Target2",
                            dependencies: ["foos"]),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes, packageKind: .remote) { _, diagnostics in
                diagnostics.checkUnordered(diagnostic: "unknown package 'foo1' in dependencies of target 'Target1'", behavior: .error)
                diagnostics.checkUnordered(diagnostic: "unknown dependency 'foos' in target 'Target2'", behavior: .error)
            }
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
                            name: "Target1",
                            dependencies: [.product(name: "product", package: "foo1")]),
                        .target(
                            name: "Target2",
                            dependencies: ["foos"]),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes, packageKind: .root) { _, diagnostics in
                diagnostics.checkUnordered(diagnostic: "unknown package 'foo1' in dependencies of target 'Target1'", behavior: .error)
            }
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
            let targetFoo = manifest.targetMap["foo"]!
            let targetBar = manifest.targetMap["bar"]!
            XCTAssertEqual(manifest.packageDependency(referencedBy: targetFoo.dependencies[0]), dependencyFoobar)
            XCTAssertEqual(manifest.packageDependency(referencedBy: targetFoo.dependencies[1]), dependencyBarfoo)
            XCTAssertEqual(manifest.packageDependency(referencedBy: targetBar.dependencies[0]), nil)
        }
    }

    func testDuplicateDependencyNames() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [],
                dependencies: [
                    .package(name: "Bar", url: "/bar1", from: "1.0.0"),
                    .package(name: "Bar", path: "/bar2"),
                    .package(name: "Biz", url: "/biz1", from: "1.0.0"),
                    .package(name: "Biz", path: "/biz2"),
                ],
                targets: [
                    .target(
                        name: "Foo",
                        dependencies: [
                            .product(name: "Something", package: "Bar"),
                            .product(name: "Something", package: "Biz"),
                        ]),
                ]
            )
            """

        XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
            diagnostics.checkUnordered(diagnostic: "duplicate dependency named 'Bar'; consider differentiating them using the 'name' argument", behavior: .error)
            diagnostics.checkUnordered(diagnostic: "duplicate dependency named 'Biz'; consider differentiating them using the 'name' argument", behavior: .error)
        }
    }

    func testResourcesUnavailable() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .target(
                       name: "Foo",
                       resources: [
                           .copy("foo.txt"),
                           .process("bar.txt"),
                       ]
                   ),
               ]
            )
            """

        XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("\(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5.3"))
        }
    }

    func testBinaryTargetUnavailable() throws {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            path: "../Foo.xcframework"),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
                guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                    return XCTFail("\(error)")
                }

                XCTAssertMatch(message, .contains("is unavailable"))
                XCTAssertMatch(message, .contains("was introduced in PackageDescription 5.3"))
            }
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            url: "https://foo.com/foo.zip",
                            checksum: "21321441231232"),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
                guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                    return XCTFail("\(error)")
                }

                XCTAssertMatch(message, .contains("is unavailable"))
                XCTAssertMatch(message, .contains("was introduced in PackageDescription 5.3"))
            }
        }
    }

    func testConditionalTargetDependenciesUnavailable() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [
                    .package(path: "/Baz"),
                ],
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Biz"),
                        .target(name: "Bar", condition: .when(platforms: [.linux])),
                    ]),
                    .target(name: "Bar"),
                ]
            )
            """

        XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("\(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5.3"))
        }
    }

    func testDefaultLocalizationUnavailable() throws {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    defaultLocalization: "fr",
                    products: [],
                    targets: [
                        .target(name: "Foo"),
                    ]
                )
                """

            do {
                try loadManifestThrowing(stream.bytes) { _ in }
                XCTFail()
            } catch {
                guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                    return XCTFail("\(error)")
                }

                XCTAssertMatch(message, .contains("is unavailable"))
                XCTAssertMatch(message, .contains("was introduced in PackageDescription 5.3"))
            }
        }
    }

    func testManifestLoadingIsSandboxed() throws {
        #if os(macOS) // Sandboxing is only done on macOS today.
        let stream = BufferedOutputByteStream()
        stream <<< """
            import Foundation

            try! String(contentsOf:URL(string: "http://127.0.0.1")!)

            import PackageDescription
            let package = Package(
                name: "Foo",
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """

        XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
            guard case ManifestParseError.invalidManifestFormat(let msg, _) = error else { return XCTFail("unexpected error: \(error)") }
            XCTAssertTrue(msg.contains("Operation not permitted"), "unexpected error message: \(msg)")
        }
        #endif
    }
}
