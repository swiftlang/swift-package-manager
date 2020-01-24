/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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

class PackageDescriptionNextLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .vNext
    }

    func testResources() throws {
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

        loadManifest(stream.bytes) { manifest in
            let resources = manifest.targets[0].resources
            XCTAssertEqual(resources[0], TargetDescription.Resource(rule: .copy, path: "foo.txt"))
            XCTAssertEqual(resources[1], TargetDescription.Resource(rule: .process, path: "bar.txt"))
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
                        .library(name: "FooLibrary", type: .static, targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(name: "Foo", path: "Foo.zip"),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryProductType(let productName) {
            XCTAssertEqual(productName, "FooLibrary")
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
                        .executable(name: "FooLibrary", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(name: "Foo", path: "Foo.zip"),
                    ]
                )
                """

            try loadManifestThrowing(stream.bytes) { manifest in
                return XCTFail("did not generate eror")
            }
        } catch ManifestParseError.invalidBinaryProductType(let productName) {
            XCTAssertEqual(productName, "FooLibrary")
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
                        .library(name: "FooLibrary", type: .static, targets: ["Foo", "Bar"]),
                    ],
                    targets: [
                        .binaryTarget(name: "Foo", path: "Foo.zip"),
                        .target(name: "Bar"),
                    ]
                )
                """

            loadManifest(stream.bytes) { _ in }
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
                        .binaryTarget(name: "Foo", path: " "),
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
                        .binaryTarget(name: "Foo", path: "../Foo"),
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
                        .binaryTarget(name: "Foo", path: "../Foo.a"),
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
