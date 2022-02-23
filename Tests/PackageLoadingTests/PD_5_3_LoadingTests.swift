/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageModel
import PackageLoading
import SPMTestSupport
import TSCBasic
import XCTest

class PackageDescription5_3LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_3
    }

    func testResources() throws {
        let content = """
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

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let resources = manifest.targets[0].resources
        XCTAssertEqual(resources[0], TargetDescription.Resource(rule: .copy, path: "foo.txt"))
        XCTAssertEqual(resources[1], TargetDescription.Resource(rule: .process(localization: .none), path: "bar.txt"))
        XCTAssertEqual(resources[2], TargetDescription.Resource(rule: .process(localization: .default), path: "biz.txt"))
        XCTAssertEqual(resources[3], TargetDescription.Resource(rule: .process(localization: .base), path: "baz.txt"))

        let testResources = manifest.targets[1].resources
        XCTAssertEqual(testResources[0], TargetDescription.Resource(rule: .process(localization: .none), path: "testfixture.txt"))
    }

    func testBinaryTargetsTrivial() throws {
        let content = """
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
                    .binaryTarget(
                        name: "Foo3",
                        path: "./Foo3.zip"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let targets = Dictionary(uniqueKeysWithValues: manifest.targets.map({ ($0.name, $0) }))
        let foo1 = targets["Foo1"]!
        let foo2 = targets["Foo2"]!
        let foo3 = targets["Foo3"]
        XCTAssertEqual(foo1, try? TargetDescription(
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
        XCTAssertEqual(foo2, try? TargetDescription(
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
        XCTAssertEqual(foo3, try? TargetDescription(
            name: "Foo3",
            dependencies: [],
            path: "./Foo3.zip",
            url: nil,
            exclude: [],
            sources: nil,
            resources: [],
            publicHeadersPath: nil,
            type: .binary,
            pkgConfig: nil,
            providers: nil,
            settings: [],
            checksum: nil
        ))
    }

    func testBinaryTargetsDisallowedProperties() throws {
        let content = """
            import PackageDescription
            var fwBinaryTarget = Target.binaryTarget(
                name: "Foo",
                url: "https://example.com/foo.git",
                checksum: "xyz"
            )
            fwBinaryTarget.linkerSettings = [ .linkedFramework("AVFoundation") ]
            let package = Package(name: "foo", targets: [fwBinaryTarget])
            """

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            XCTAssertEqual(error.localizedDescription, "target 'Foo' contains a value for disallowed property 'settings'")
        }
    }

    func testBinaryTargetsValidation() throws {
        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid type for binary product 'FooLibrary'; products referencing only binary targets must have a type of 'library'", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid type for binary product 'FooLibrary'; products referencing only binary targets must have a type of 'library'", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            _ = try loadManifest(content, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid local path ' ' for binary target 'Foo', path expected to be relative to package root.", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid URL scheme for binary target 'Foo'; valid schemes are: 'https'", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: 'zip', 'xcframework', 'artifactbundle'", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: 'zip'", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: 'zip', 'xcframework', 'artifactbundle'", severity: .error)
            }
        }

        do {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "unsupported extension for binary target 'Foo'; valid extensions are: 'zip'", severity: .error)
            }
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            url: "ssh://foo/bar",
                            checksum: "839F9F30DC13C30795666DD8F6FB77DD0E097B83D06954073E34FE5154481F7A"),
                    ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid URL scheme for binary target 'Foo'; valid schemes are: 'https'", severity: .error)
            }
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            url: " ",
                            checksum: "839F9F30DC13C30795666DD8F6FB77DD0E097B83D06954073E34FE5154481F7A"),
                    ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid URL ' ' for binary target 'Foo'", severity: .error)
            }
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                    name: "Foo",
                    products: [
                        .library(name: "Foo", targets: ["Foo"]),
                    ],
                    targets: [
                        .binaryTarget(
                            name: "Foo",
                            path: "/tmp/foo/bar")
                    ]
                )
                """

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error")
            testDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: "invalid local path '/tmp/foo/bar' for binary target 'Foo', path expected to be relative to package root.", severity: .error)
            }
        }
    }

    func testConditionalTargetDependencies() throws {
        let content = """
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

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let dependencies = manifest.targets[0].dependencies
        XCTAssertEqual(dependencies[0], .target(name: "Biz"))
        XCTAssertEqual(dependencies[1], .target(name: "Bar", condition: .init(platformNames: ["linux"], config: nil)))
        XCTAssertEqual(dependencies[2], .product(name: "Baz", package: "Baz", condition: .init(platformNames: ["macos"])))
        XCTAssertEqual(dependencies[3], .byName(name: "Bar", condition: .init(platformNames: ["watchos", "ios"])))

    }

    func testDefaultLocalization() throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                defaultLocalization: "fr",
                targets: [
                    .target(name: "Foo"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertEqual(manifest.defaultLocalization, "fr")
    }

    func testTargetPathsValidation() throws {
        let manifestItemToDiagnosticMap = [
            "sources: [\"/foo.swift\"]": "invalid relative path '/foo.swift",
            "resources: [.copy(\"/foo.txt\")]": "invalid relative path '/foo.txt'",
            "exclude: [\"/foo.md\"]": "invalid relative path '/foo.md",
        ]

        for (manifestItem, expectedDiag) in manifestItemToDiagnosticMap {
            let content = """
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

            let observability = ObservabilitySystem.makeForTesting()
            XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error") { error in
                if let error = error as? PathValidationError {
                    XCTAssertMatch(error.description, .contains(expectedDiag))
                } else {
                    XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testNonZeroExitStatusDoesNotAssert() throws {
        let content = """
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

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            XCTAssertNotNil(error as? ManifestParseError)
        }
    }

    func testManifestLoadingIsSandboxed() throws {
        #if !os(macOS)
        // Sandboxing is only done on macOS today.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let content = """
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

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            if case ManifestParseError.invalidManifestFormat(let error, _) = error {
                XCTAssertTrue(error.contains("Operation not permitted"), "unexpected error message: \(error)")
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}
