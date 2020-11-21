/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

@testable import SPMPackageEditor

final class AddProductTests: XCTestCase {
    func testAddTarget() throws {
        let manifest = """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                products: [
                    .executable(name: "abc", targets: ["foo"]),
                ]
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
        try editor.addProduct(name: "exec", type: .executable)
        try editor.addProduct(name: "lib", type: .library(.automatic))
        try editor.addProduct(name: "staticLib", type: .library(.static))
        try editor.addProduct(name: "dynamicLib", type: .library(.dynamic))

        XCTAssertEqual(editor.editedManifest, """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                products: [
                    .executable(name: "abc", targets: ["foo"]),
                    .executable(
                        name: "exec",
                        targets: []),
                    .library(
                        name: "lib",
                        targets: []),
                    .library(
                        name: "staticLib",
                        type: .static,
                        targets: []),
                    .library(
                        name: "dynamicLib",
                        type: .dynamic,
                        targets: []),
                ]
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
            """)
    }

    func testAddTarget2() throws {
        let manifest = """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
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
        try editor.addProduct(name: "exec", type: .executable)
        try editor.addProduct(name: "lib", type: .library(.automatic))
        try editor.addProduct(name: "staticLib", type: .library(.static))
        try editor.addProduct(name: "dynamicLib", type: .library(.dynamic))

        // FIXME: weird indentation
        XCTAssertEqual(editor.editedManifest, """
            // swift-tools-version:5.2
            import PackageDescription

            let package = Package(
                name: "exec",
                products: [
                    .executable(
                        name: "exec",
                        targets: []),
                    .library(
                        name: "lib",
                        targets: []),
                    .library(
                        name: "staticLib",
                        type: .static,
                        targets: []),
                    .library(
                        name: "dynamicLib",
                        type: .dynamic,
                        targets: []),],
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
            """)
    }
}
