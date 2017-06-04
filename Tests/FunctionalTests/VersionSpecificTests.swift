/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import SourceControl
import Utility

import TestSupport

class VersionSpecificTests: XCTestCase {
    /// Functional tests of end-to-end support for version specific dependency resolution.
    func testEndToEndResolution() throws {
        mktmpdir { path in
            var fs = localFileSystem

            // Create a repo for the dependency to test against.
            let depPath = path.appending(component: "Dep")
            try fs.createDirectory(depPath)
            initGitRepo(depPath)
            let repo = GitRepository(path: depPath)

            // Create the initial commit.
            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                $0 <<< "import PackageDescription\n"
                $0 <<< "let package = Package(name: \"Dep\")\n"
            }
            try repo.stage(file: "Package.swift")
            try repo.commit(message: "Initial")
            try repo.tag(name: "1.0.0")

            // Create the version to test against.
            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                $0 <<< "NOT_A_VALID_PACKAGE"
            }
            try fs.writeFileContents(depPath.appending(component: "foo.swift")) {
                $0 <<< "public func foo() { print(\"foo\\n\") }\n"
            }
            try repo.stage(file: "Package.swift")
            try repo.stage(file: "foo.swift")
            try repo.commit(message: "Bogus v1.1.0")
            try repo.tag(name: "1.1.0")

            // Create the primary repository.
            let primaryPath = path.appending(component: "Primary")
            try fs.writeFileContents(primaryPath.appending(component: "Package.swift")) {
                $0 <<< "import PackageDescription\n"
                $0 <<< "let package = Package(name: \"Primary\", dependencies: [.Package(url: \"../Dep\", majorVersion: 1)])\n"
            }
            // This build should fail, because of the invalid package.
            XCTAssertBuildFails(primaryPath)

            // Create a file which requires a version 1.1.0 resolution.
            try fs.writeFileContents(primaryPath.appending(component: "main.swift")) {
                $0 <<< "import Dep\n"
                $0 <<< "Dep.foo()\n"
            }

            // Create a version-specific tag, which should work.
            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                $0 <<< "import PackageDescription\n"
                $0 <<< "let package = Package(name: \"Dep\")\n"
            }
            try repo.stage(file: "Package.swift")
            try repo.commit(message: "OK v1.1.0")
            try repo.tag(name: "1.1.0@swift-\(Versioning.currentVersion.major)")

            // The build should work now.
            _ = try SwiftPMProduct.SwiftPackage.execute(["reset"], packagePath: primaryPath)
            XCTAssertBuilds(primaryPath)
        }
    }

    static var allTests = [
        ("testEndToEndResolution", testEndToEndResolution),
    ]
}
