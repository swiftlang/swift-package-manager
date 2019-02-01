/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

@testable import SPMPackageEditor

final class AddTargetDependencyTests: XCTestCase {
    func testAddTargetDependency() throws {
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
                        name: "a",
                        dependencies: []),
                    .target(
                        name: "exec",
                        dependencies: []),
                    .target(
                        name: "c",
                        dependencies: []),
                    .testTarget(
                        name: "execTests",
                        dependencies: ["exec"]),
                ]
            )
            """
        
        let editor = try ManifestRewriter(manifest)
        try editor.addTargetDependency(
            target: "exec", dependency: "foo")
        try editor.addTargetDependency(
            target: "exec", dependency: "bar")
        try editor.addTargetDependency(
            target: "execTests", dependency: "foo")

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
                        name: "a",
                        dependencies: []),
                    .target(
                        name: "exec",
                        dependencies: ["foo", "bar"]),
                    .target(
                        name: "c",
                        dependencies: []),
                    .testTarget(
                        name: "execTests",
                        dependencies: ["exec", "foo"]),
                ]
            )
            """)
    }

    func testAddTargetDependency2() throws {
        let manifest = """
            let package = Package(
                name: "exec",
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["bar"]),
                    .target(
                        name: "foo1",
                        dependencies: ["bar",]),
                    .target(
                        name: "foo2",
                        dependencies: []),
                    .target(
                        name: "foo3",
                        dependencies: ["foo", "bar"]),
                    .target(
                        name: "foo4",
                        dependencies: [
                            "foo", "bar"
                        ]),
                ]
            )
            """

        let editor = try ManifestRewriter(manifest)
        try editor.addTargetDependency(
            target: "foo", dependency: "dep")
        try editor.addTargetDependency(
            target: "foo1", dependency: "dep")
        try editor.addTargetDependency(
            target: "foo2", dependency: "dep")
        try editor.addTargetDependency(
            target: "foo3", dependency: "dep")
        try editor.addTargetDependency(
            target: "foo4", dependency: "dep")

        XCTAssertEqual(editor.editedManifest, """
            let package = Package(
                name: "exec",
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["bar", "dep"]),
                    .target(
                        name: "foo1",
                        dependencies: ["bar", "dep"]),
                    .target(
                        name: "foo2",
                        dependencies: ["dep"]),
                    .target(
                        name: "foo3",
                        dependencies: ["foo", "bar", "dep"]),
                    .target(
                        name: "foo4",
                        dependencies: [
                            "foo", "bar", "dep"
                        ]),
                ]
            )
            """)
    }

}
