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

    func testBinaryTargetsTrivial() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [
                    .library(name: "Foo1", targets: ["Foo1"]),
                    .library(name: "Foo2", targets: ["Foo2"])
                ],
                targets: [
                    .binaryTarget(
                        name: "Foo1",
                        path: "../Foo1.xcframework"),
                    .binaryTarget(
                        name: "Foo2",
                        url: "https://foo.com/Foo2-1.0.0.zip",
                        checksum: "839F9F30DC13C30795666DD8F6FB77DD0E097B83D06954073E34FE5154481F7A"),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            let targets = Dictionary(uniqueKeysWithValues: manifest.targets.map({ ($0.name, $0) }))
            let foo1 = targets["Foo1"]!
            let foo2 = targets["Foo2"]!
            XCTAssertEqual(foo1, TargetDescription(
                name: "Foo1",
                dependencies: [],
                path: "../Foo1.xcframework",
                url: nil,
                exclude: [],
                sources: nil,
                resources: [],
                publicHeadersPath: nil,
                type: .binary,
                pkgConfig: nil,
                providers: nil,
                settings: [],
                checksum: nil))
            XCTAssertEqual(foo2, TargetDescription(
                name: "Foo2",
                dependencies: [],
                path: nil,
                url: "https://foo.com/Foo2-1.0.0.zip",
                exclude: [],
                sources: nil,
                resources: [],
                publicHeadersPath: nil,
                type: .binary,
                pkgConfig: nil,
                providers: nil,
                settings: [],
                checksum: "839F9F30DC13C30795666DD8F6FB77DD0E097B83D06954073E34FE5154481F7A"))
        }
    }

    func testBinaryTargetsValidation() {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            path: " "),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryLocation(let targetName) {
            XCTAssertEqual(targetName, "Foo")
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            path: "../Foo"),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryLocationExtension(let targetName, let validExtensions) {
            XCTAssertEqual(targetName, "Foo")
            XCTAssertEqual(Set(validExtensions), ["zip", "xcframework"])
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            url: "https://foo.com/foo-1",
                            checksum: "839F9F30DC13C30795666DD8F6FB77DD0E097B83D06954073E34FE5154481F7A"),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryLocationExtension(let targetName, let validExtensions) {
            XCTAssertEqual(targetName, "Foo")
            XCTAssertEqual(Set(validExtensions), ["zip"])
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            path: "../Foo.a"),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryLocationExtension(let targetName, let validExtensions) {
            XCTAssertEqual(targetName, "Foo")
            XCTAssertEqual(Set(validExtensions), ["zip", "xcframework"])
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            url: "https://foo.com/foo-1.0.0.xcframework",
                            checksum: "839F9F30DC13C30795666DD8F6FB77DD0E097B83D06954073E34FE5154481F7A"),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryLocationExtension(let targetName, let validExtensions) {
            XCTAssertEqual(targetName, "Foo")
            XCTAssertEqual(Set(validExtensions), ["zip"])
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}
