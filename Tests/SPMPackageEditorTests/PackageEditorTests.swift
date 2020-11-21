/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import SPMTestSupport

@testable import SPMPackageEditor

final class PackageEditorTests: XCTestCase {
    func testAddTarget() throws {
        let manifest = """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                ]
            )
            """

        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Package.swift",
            "/pkg/Sources/foo/source.swift",
            "/pkg/Sources/bar/source.swift",
            "/pkg/Tests/fooTests/source.swift",
            "end")

        let manifestPath = AbsolutePath("/pkg/Package.swift")
        try fs.writeFileContents(manifestPath) { $0 <<< manifest }

        let context = try PackageEditorContext(
            manifestPath: AbsolutePath("/pkg/Package.swift"),
            buildDir: AbsolutePath("/pkg/foo"), toolchain: Resources.default.toolchain, fs: fs)
        let editor = PackageEditor(context: context)

        XCTAssertThrows(StringError("a target named 'foo' already exists")) {
            try editor.addTarget(name: "foo", type: .regular)
        }

        try editor.addTarget(name: "baz", type: .regular)

        let newManifest = try fs.readFileContents(manifestPath).cString
        XCTAssertEqual(newManifest, """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                    .target(
                        name: "baz",
                        dependencies: []),
                    .testTarget(
                        name: "bazTests",
                        dependencies: ["baz"]),
                ]
            )
            """)

        XCTAssertTrue(fs.exists(AbsolutePath("/pkg/Sources/baz/baz.swift")))
        XCTAssertTrue(fs.exists(AbsolutePath("/pkg/Tests/bazTests/bazTests.swift")))
    }

    func testToolsVersionTest() throws {
        let manifest = """
            // swift-tools-version:5.0
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: []),
                ]
            )
            """

        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Package.swift",
            "/pkg/Sources/foo/source.swift",
            "end")

        let manifestPath = AbsolutePath("/pkg/Package.swift")
        try fs.writeFileContents(manifestPath) { $0 <<< manifest }

        let context = try PackageEditorContext(
            manifestPath: AbsolutePath("/pkg/Package.swift"),
            buildDir: AbsolutePath("/pkg/foo"), toolchain: Resources.default.toolchain, fs: fs)
        let editor = PackageEditor(context: context)

        XCTAssertThrows(StringError("mechanical manifest editing operations are only supported for packages with swift-tools-version 5.2 and later")) {
            try editor.addTarget(name: "bar", type: .regular)
        }
    }
}
