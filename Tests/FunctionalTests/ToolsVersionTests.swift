/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility
import TestSupport
import Commands
import PackageModel
import SourceControl

class ToolsVersionTests: XCTestCase {

    func testToolsVersion() throws {
        mktmpdir { path in
            var fs = localFileSystem

            // Create a repo for the dependency to test against.
            let depPath = path.appending(component: "Dep")
            try fs.createDirectory(depPath)
            initGitRepo(depPath)
            let repo = GitRepository(path: depPath)

            try fs.writeFileContents(depPath.appending(component: "Package.swift")) {
                $0 <<< """
                    // swift-tools-version:3.1
                    import PackageDescription
                    let package = Package(name: "Dep")
                    """
            }
            try fs.writeFileContents(depPath.appending(component: "foo.swift")) {
                $0 <<< """
                    public func foo() { print("foo@1.0") }
                    """
            }
            // v1.
            try repo.stageEverything()
            try repo.commit(message: "Initial")
            try repo.tag(name: "1.0.0")

            // v1.0.1
            _ = try SwiftPMProduct.SwiftPackage.execute(
                ["tools-version", "--set", "10000.1"], packagePath: depPath)
            try fs.writeFileContents(depPath.appending(component: "foo.swift")) {
                $0 <<< """
                    public func foo() { print("foo@1.0.1") }
                    """
            }
            try repo.stageEverything()
            try repo.commit(message: "1.0.1")
            try repo.tag(name: "1.0.1")

            // Create the primary repository.
            let primaryPath = path.appending(component: "Primary")
            try fs.writeFileContents(primaryPath.appending(component: "Package.swift")) {
                $0 <<< """
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [.package(url: "../Dep", from: "1.0.0")],
                        targets: [.target(name: "Primary", dependencies: ["Dep"], path: ".")]
                    )
                    """
            }
            // Create a file.
            try fs.writeFileContents(primaryPath.appending(component: "main.swift")) {
                $0 <<< """
                    import Dep
                    Dep.foo()
                    """
            }
            _ = try SwiftPMProduct.SwiftPackage.execute(
                ["tools-version", "--set-current"], packagePath: primaryPath).chomp()

            // Build the primary package.
            _ = try SwiftPMProduct.SwiftBuild.execute([], packagePath: primaryPath)
            let exe = primaryPath.appending(components: ".build", Destination.host.target, "debug", "Primary").asString
            // v1 should get selected because v1.0.1 depends on a (way) higher set of tools.
            XCTAssertEqual(try Process.checkNonZeroExit(args: exe).chomp(), "foo@1.0")

            // Set the tools version to something high.
            _ = try SwiftPMProduct.SwiftPackage.execute(
                ["tools-version", "--set", "10000.1"], packagePath: primaryPath).chomp()

            do {
                _ = try SwiftPMProduct.SwiftBuild.execute([], packagePath: primaryPath)
                XCTFail()
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssert(stderr.contains("equires a minimum Swift tools version of 10000.1.0 (currently 4.0.0)"))
            }

            // Write the manifest with incompatible sources.
            try fs.writeFileContents(primaryPath.appending(component: "Package.swift")) {
                $0 <<< """
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [.package(url: "../Dep", from: "1.0.0")],
                        targets: [.target(name: "Primary", dependencies: ["Dep"], path: ".")],
                        swiftLanguageVersions: [1000])
                    """
            }
            _ = try SwiftPMProduct.SwiftPackage.execute(
                ["tools-version", "--set-current"], packagePath: primaryPath).chomp()

            do {
                _ = try SwiftPMProduct.SwiftBuild.execute([], packagePath: primaryPath)
                XCTFail()
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertTrue(
                    stderr.contains("package 'Primary' not compatible with current tools version (") &&
                    stderr.contains("); it supports: 1000\n"))
            }

             try fs.writeFileContents(primaryPath.appending(component: "Package.swift")) {
                $0 <<< """
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [.package(url: "../Dep", from: "1.0.0")], 
                        targets: [.target(name: "Primary", dependencies: ["Dep"], path: ".")],
                        swiftLanguageVersions: [\(ToolsVersion.currentToolsVersion.major), 1000])
                    """
             }
             _ = try SwiftPMProduct.SwiftPackage.execute(
                 ["tools-version", "--set-current"], packagePath: primaryPath).chomp()
             _ = try SwiftPMProduct.SwiftBuild.execute([], packagePath: primaryPath)
        }
    }

    static var allTests = [
        ("testToolsVersion", testToolsVersion),
    ]
}
