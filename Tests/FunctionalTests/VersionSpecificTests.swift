/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import SourceControl
import TSCUtility

import SPMTestSupport

class VersionSpecificTests: XCTestCase {
    /// Functional tests of end-to-end support for version specific dependency resolution.
    func testEndToEndResolution() throws {
        try testWithTemporaryDirectory{ path in
            let fs = localFileSystem

            // Create a repo for the dependency to test against.
            let depPath = path.appending(component: "Dep")
            try fs.createDirectory(depPath)
            initGitRepo(depPath)
            let repo = GitRepository(path: depPath)

            // Create the initial commit.
            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                $0 <<< """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "Dep",
                        products: [
                            .library(name: "Dep", targets: ["Dep"]),
                        ],
                        targets: [
                            .target(name: "Dep", path: "./")
                        ]
                    )
                    """
            }
            try repo.stage(file: "Package.swift")
            try repo.commit(message: "Initial")
            try repo.tag(name: "1.0.0")

            // Create the version to test against.
            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                // FIXME: We end up filtering this manifest if it has an invalid
                // tools version as they're assumed to be v3 manifests. Should we
                // do something better?
                $0 <<< "// swift-tools-version:4.2\n"
                $0 <<< "NOT_A_VALID_PACKAGE"
            }
            try fs.writeFileContents(depPath.appending(component: "foo.swift")) {
                $0 <<< """
                    public func foo() { print("foo\\n") }
                    """
            }
            try repo.stage(file: "Package.swift")
            try repo.stage(file: "foo.swift")
            try repo.commit(message: "Bogus v1.1.0")
            try repo.tag(name: "1.1.0")

            // Create the primary repository.
            let primaryPath = path.appending(component: "Primary")
            try fs.writeFileContents(primaryPath.appending(component: "Package.swift")) {
                $0 <<< """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [
                            .package(url: "../Dep", from: "1.0.0"),
                        ],
                        targets: [
                            .target(name: "Primary", dependencies: ["Dep"], path: "./")
                        ]
                    )
                    """
            }
            // This build should fail, because of the invalid package.
            XCTAssertBuildFails(primaryPath)

            // Create a file which requires a version 1.1.0 resolution.
            try fs.writeFileContents(primaryPath.appending(component: "main.swift")) {
                $0 <<< """
                    import Dep
                    Dep.foo()
                    """
            }

            // Create a version-specific tag, which should work.
            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                $0 <<< """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "Dep",
                        products: [
                            .library(name: "Dep", targets: ["Dep"]),
                        ],
                        targets: [
                            .target(name: "Dep", path: "./")
                        ]
                    )
                    """
            }
            try repo.stage(file: "Package.swift")
            try repo.commit(message: "OK v1.1.0")
            try repo.tag(name: "1.1.0@swift-\(Versioning.currentVersion.major)")

            // The build should work now.
            _ = try SwiftPMProduct.SwiftPackage.execute(["reset"], packagePath: primaryPath)
            XCTAssertBuilds(primaryPath)
        }
    }
}
