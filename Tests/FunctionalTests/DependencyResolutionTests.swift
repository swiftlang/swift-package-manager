//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Commands
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

class DependencyResolutionTests: XCTestCase {
    func testInternalSimple() throws {
        try fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            XCTAssertBuilds(fixturePath)

            let output = try Process.checkNonZeroExit(args: fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Foo").pathString)
            XCTAssertEqual(output, "Foo\nBar\n")
        }
    }

    func testInternalExecAsDep() throws {
        try fixture(name: "DependencyResolution/Internal/InternalExecutableAsDependency") { fixturePath in
            XCTAssertBuildFails(fixturePath)
        }
    }

    func testInternalComplex() throws {
        try fixture(name: "DependencyResolution/Internal/Complex") { fixturePath in
            XCTAssertBuilds(fixturePath)

            let output = try Process.checkNonZeroExit(args: fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Foo").pathString)
            XCTAssertEqual(output, "meiow Baz\n")
        }
    }

    /// Check resolution of a trivial package with one dependency.
    func testExternalSimple() throws {
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            // Add several other tags to check version selection.
            let repo = GitRepository(path: fixturePath.appending(components: "Foo"))
            for tag in ["1.1.0", "1.2.0"] {
                try repo.tag(name: tag)
            }

            let packageRoot = fixturePath.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(fixturePath.appending(components: "Bar", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Bar"))
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssert(try GitRepository(path: path).getTags().contains("1.2.3"))
        }
    }

    func testExternalComplex() throws {
        try fixture(name: "DependencyResolution/External/Complex") { fixturePath in
            XCTAssertBuilds(fixturePath.appending(component: "app"))
            let output = try Process.checkNonZeroExit(args: fixturePath.appending(components: "app", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Dealer").pathString)
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }
    
    func testConvenienceBranchInit() throws {
        try fixture(name: "DependencyResolution/External/Branch") { fixturePath in
            // Tests the convenience init .package(url: , branch: )
            let app = fixturePath.appending(component: "Bar")
            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: app)
            XCTAssertEqual(result.exitStatus, .terminated(code: 0))
        }
    }

    func testMirrors() throws {
        try fixture(name: "DependencyResolution/External/Mirror") { fixturePath in
            let prefix = resolveSymlinks(fixturePath)
            let appPath = prefix.appending(component: "App")
            let appPinsPath = appPath.appending(component: "Package.resolved")

            // prepare the dependencies as git repos
            try ["Foo", "Bar", "BarMirror"].forEach { directory in
                let path = prefix.appending(component: directory)
                _ = try Process.checkNonZeroExit(args: "git", "-C", path.pathString, "init")
                _ = try Process.checkNonZeroExit(args: "git", "-C", path.pathString, "checkout", "-b", "newMain")
            }

            // run with no mirror
            do {
                let output = try executeSwiftPackage(appPath, extraArgs: ["show-dependencies"])
                // logs are in stderr
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.pathString)/Foo\n"))
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.pathString)/Bar\n"))
                // results are in stdout
                XCTAssertMatch(output.stdout, .contains("foo<\(prefix.pathString)/Foo@unspecified"))
                XCTAssertMatch(output.stdout, .contains("bar<\(prefix.pathString)/Bar@unspecified"))

                let pins: String = try localFileSystem.readFileContents(appPinsPath)
                XCTAssertMatch(pins, .contains("\"\(prefix.pathString)/Foo\""))
                XCTAssertMatch(pins, .contains("\"\(prefix.pathString)/Bar\""))

                XCTAssertBuilds(appPath)
            }

            // clean
            try localFileSystem.removeFileTree(appPath.appending(component: ".build"))
            try localFileSystem.removeFileTree(appPinsPath)

            // set mirror
            _ = try executeSwiftPackage(appPath, extraArgs: ["config", "set-mirror",
                                                              "--original-url", prefix.appending(component: "Bar").pathString,
                                                              "--mirror-url", prefix.appending(component: "BarMirror").pathString])

            // run with mirror
            do {
                let output = try executeSwiftPackage(appPath, extraArgs: ["show-dependencies"])
                // logs are in stderr
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.pathString)/Foo\n"))
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.pathString)/BarMirror\n"))
                XCTAssertNoMatch(output.stderr, .contains("Fetching \(prefix.pathString)/Bar\n"))
                // result are in stdout
                XCTAssertMatch(output.stdout, .contains("foo<\(prefix.pathString)/Foo@unspecified"))
                XCTAssertMatch(output.stdout, .contains("barmirror<\(prefix.pathString)/BarMirror@unspecified"))
                XCTAssertNoMatch(output.stdout, .contains("bar<\(prefix.pathString)/Bar@unspecified"))

                // rdar://52529014 mirrors should not be reflected in pins file
                let pins: String = try localFileSystem.readFileContents(appPinsPath)
                XCTAssertMatch(pins, .contains("\"\(prefix.pathString)/Foo\""))
                XCTAssertMatch(pins, .contains("\"\(prefix.pathString)/Bar\""))
                XCTAssertNoMatch(pins, .contains("\"\(prefix.pathString)/BarMirror\""))

                XCTAssertBuilds(appPath)
            }
        }
    }

    func testPackageLookupCaseInsensitive() throws {
        try fixture(name: "DependencyResolution/External/PackageLookupCaseInsensitive") { fixturePath in
            let result = try SwiftPMProduct.SwiftPackage.executeProcess(["update"], packagePath: fixturePath.appending(component: "pkg"))
            XCTAssert(result.exitStatus == .terminated(code: 0), try! result.utf8Output() + result.utf8stderrOutput())
        }
    }
}
