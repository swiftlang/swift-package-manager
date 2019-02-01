/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

@testable import SPMPackageEditor

final class AddTargetTests: XCTestCase {
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
        
        let editor = try ManifestRewriter(manifest)
        try editor.addTarget(targetName: "NewTarget")
        try editor.addTarget(targetName: "NewTargetTests", type: .test)
        try editor.addTargetDependency(target: "NewTargetTests", dependency: "NewTarget")

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
                        name: "foo",
                        dependencies: []),
                    .target(
                        name: "bar",
                        dependencies: []),
                    .testTarget(
                        name: "fooTests",
                        dependencies: ["foo", "bar"]),
                    .target(
                        name: "NewTarget",
                        dependencies: []),
                    .testTarget(
                        name: "NewTargetTests",
                        dependencies: ["NewTarget"]),
                ]
            )
            """)
    }
}
