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
            buildDir: AbsolutePath("/pkg/foo"), fs: fs)
        let editor = PackageEditor(context: context)

        XCTAssertThrows(StringError("Already has a target named foo")) {
            try editor.addTarget(options:
                .init(manifestPath: manifestPath, targetName: "foo"))
        }

        try editor.addTarget(options:
            .init(manifestPath: manifestPath, targetName: "baz"))

        let newManifest = try fs.readFileContents(manifestPath).cString
        XCTAssertEqual(newManifest, """
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
}
