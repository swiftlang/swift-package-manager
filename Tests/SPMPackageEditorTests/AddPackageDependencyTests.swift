/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

@testable import SPMPackageEditor

final class AddPackageDependencyTests: XCTestCase {
    func testAddPackageDependency() throws {
        let manifest = """
            // swift-tools-version:5.0
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                ],
                targets: [
                    .target(
                        name: "exec",
                        dependencies: []),
                    .testTarget(
                        name: "execTests",
                        dependencies: ["exec"]),
                ]
            )
            """
        
        
        let editor = try ManifestRewriter(manifest)
        try editor.addPackageDependency(
            url: "https://github.com/foo/goo",
            requirement: .upToNextMajor("1.0.1")
        )
        
        XCTAssertEqual(editor.editedManifest, """
            // swift-tools-version:5.0
            import PackageDescription

            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "exec",
                        dependencies: []),
                    .testTarget(
                        name: "execTests",
                        dependencies: ["exec"]),
                ]
            )
            """)
    }

    func testAddPackageDependency2() throws {
        let manifest = """
            let package = Package(
                name: "exec",
                dependencies: [],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """


        let editor = try ManifestRewriter(manifest)
        try editor.addPackageDependency(
            url: "https://github.com/foo/goo",
            requirement: .upToNextMajor("1.0.1")
        )

        XCTAssertEqual(editor.editedManifest, """
            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """)
    }

    func testAddPackageDependency3() throws {
        let manifest = """
            let package = Package(
                name: "exec",
                dependencies: [
                    // Here is a comment.
                    .package(url: "https://github.com/foo/bar", .branch("master")),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """


        let editor = try ManifestRewriter(manifest)
        try editor.addPackageDependency(
            url: "https://github.com/foo/goo",
            requirement: .upToNextMajor("1.0.1")
        )

        XCTAssertEqual(editor.editedManifest, """
            let package = Package(
                name: "exec",
                dependencies: [
                    // Here is a comment.
                    .package(url: "https://github.com/foo/bar", .branch("master")),
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """)
    }

    func testAddPackageDependency4() throws {
        let manifest = """
            let package = Package(
                name: "exec",
                targets: [
                    .target(name: "exec"),
                ]
            )
            """


        let editor = try ManifestRewriter(manifest)
        try editor.addPackageDependency(
            url: "https://github.com/foo/goo",
            requirement: .upToNextMajor("1.0.1")
        )

        XCTAssertEqual(editor.editedManifest, """
            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """)
    }

    func testAddPackageDependency5() throws {
        // FIXME: This is broken, we end up removing the comment.
        let manifest = """
            let package = Package(
                name: "exec",
                dependencies: [
                    // Here is a comment.
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """


        let editor = try ManifestRewriter(manifest)
        try editor.addPackageDependency(
            url: "https://github.com/foo/goo",
            requirement: .upToNextMajor("1.0.1")
        )

        XCTAssertEqual(editor.editedManifest, """
            let package = Package(
                name: "exec",
                dependencies: [
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """)
    }

    func testAddPackageDependency6() throws {
        let manifest = """
            let myDeps = [
                .package(url: "https://github.com/foo/foo", from: "1.0.2"),
            ]

            let package = Package(
                name: "exec",
                dependencies: myDeps + [
                    .package(url: "https://github.com/foo/bar", from: "1.0.3"),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """


        let editor = try ManifestRewriter(manifest)
        try editor.addPackageDependency(
            url: "https://github.com/foo/goo",
            requirement: .upToNextMajor("1.0.1")
        )

        XCTAssertEqual(editor.editedManifest, """
            let myDeps = [
                .package(url: "https://github.com/foo/foo", from: "1.0.2"),
            ]

            let package = Package(
                name: "exec",
                dependencies: myDeps + [
                    .package(url: "https://github.com/foo/bar", from: "1.0.3"),
                    .package(url: "https://github.com/foo/goo", from: "1.0.1"),
                ],
                targets: [
                    .target(name: "exec"),
                ]
            )
            """)
    }
}
