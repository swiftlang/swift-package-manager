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
        .v5_3
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
                           .process("biz.txt", localization: .default),
                           .process("baz.txt", localization: .base),
                       ]
                    ),
                    .testTarget(
                       name: "FooTests",
                       resources: [
                           .process("testfixture.txt"),
                       ]
                    ),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            let resources = manifest.targets[0].resources
            XCTAssertEqual(resources[0], TargetDescription.Resource(rule: .copy, path: "foo.txt"))
            XCTAssertEqual(resources[1], TargetDescription.Resource(rule: .process, path: "bar.txt"))
            XCTAssertEqual(resources[2], TargetDescription.Resource(rule: .process, path: "biz.txt", localization: .default))
            XCTAssertEqual(resources[3], TargetDescription.Resource(rule: .process, path: "baz.txt", localization: .base))

            let testResources = manifest.targets[1].resources
            XCTAssertEqual(testResources[0], TargetDescription.Resource(rule: .process, path: "testfixture.txt"))
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
                        .binaryTarget(name: "Foo", path: "Foo.xcframework"),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "invalid type for binary product 'FooLibrary'; products referencing only binary targets must have a type of 'library'", behavior: .error)
            }
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
                        .binaryTarget(name: "Foo", path: "Foo.xcframework"),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "invalid type for binary product 'FooLibrary'; products referencing only binary targets must have a type of 'library'", behavior: .error)
            }
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
                        .binaryTarget(name: "Foo", path: "Foo.xcframework"),
                        .target(name: "Bar"),
                    ]
                )
                """

            XCTAssertManifestLoadNoThrows(stream.bytes)
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

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "invalid location for binary target 'Foo'", behavior: .error)
            }
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
                        .binaryTarget(name: "Foo", url: "http://foo.com/foo.zip", checksum: "checksum"),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "invalid URL scheme for binary target 'Foo'; valid schemes are: https", behavior: .error)
            }
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

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: xcframework", behavior: .error)
            }
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

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: zip", behavior: .error)
            }
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

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: xcframework", behavior: .error)
            }
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

            XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
                diagnostics.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: zip", behavior: .error)
            }
        }
    }

    func testConditionalTargetDependencies() throws {
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
                        .product(name: "Baz", package: "Baz", condition: .when(platforms: [.macOS])),
                        .byName(name: "Bar", condition: .when(platforms: [.watchOS, .iOS])),
                    ]),
                    .target(name: "Bar"),
                    .target(name: "Biz"),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            let dependencies = manifest.targets[0].dependencies

            XCTAssertEqual(dependencies[0], .target(name: "Biz"))
            XCTAssertEqual(dependencies[1], .target(name: "Bar", condition: .init(platformNames: ["linux"], config: nil)))
            XCTAssertEqual(dependencies[2], .product(name: "Baz", package: "Baz", condition: .init(platformNames: ["macos"])))
            XCTAssertEqual(dependencies[3], .byName(name: "Bar", condition: .init(platformNames: ["watchos", "ios"])))
        }
    }

    func testDefaultLocalization() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Foo",
                defaultLocalization: "fr",
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """

        XCTAssertManifestLoadNoThrows(stream.bytes) { manifest, _ in
            XCTAssertEqual(manifest.defaultLocalization, "fr")
        }
    }

    func testTargetPathsValidation() throws {
        let manifestItemToDiagnosticMap = [
            "sources: [\"/foo.swift\"]": "invalid relative path '/foo.swift",
            "resources: [.copy(\"/foo.txt\")]": "invalid relative path '/foo.txt'",
            "exclude: [\"/foo.md\"]": "invalid relative path '/foo.md",
        ]

        for (manifestItem, expectedDiag) in manifestItemToDiagnosticMap {
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    targets: [
                        .target(
                            name: "Foo",
                            \(manifestItem)
                        ),
                    ]
                )
                """

            XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
                switch error {
                case let pathError as PathValidationError:
                    XCTAssertMatch(pathError.description, .contains(expectedDiag))
                default:
                    XCTFail("\(error)")
                }
            }
        }
    }

    func testNonZeroExitStatusDoesNotAssert() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            #if canImport(Glibc)
            import Glibc
            #elseif os(Windows)
            import MSVCRT
            import WinSDK
            #else
            import Darwin.C
            #endif

            print("crash")
            exit(1)
            """

        XCTAssertManifestLoadThrows(stream.bytes) { error, _ in
            XCTAssertTrue(error is ManifestParseError, "unexpected error: \(error)")
        }
    }

    func testManifestLoadingIsSandboxed() throws {
        #if os(macOS) // Sandboxing is only done on macOS today.
        let stream = BufferedOutputByteStream()
        stream <<< """
            import Foundation

            try! "should not be allowed".write(to: URL(fileURLWithPath: "/tmp/file.txt"), atomically: true, encoding: String.Encoding.utf8)

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
