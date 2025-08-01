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

import Basics
import Commands
import PackageModel
import SourceControl
import _InternalTestSupport
import Workspace
import XCTest

import enum TSCUtility.Git

class DependencyResolutionTests: XCTestCase {
    func testInternalSimple() async throws {
        try await fixtureXCTest(name: "DependencyResolution/Internal/Simple") { fixturePath in
            await XCTAssertBuilds(fixturePath, buildSystem: .native)

            let output = try await AsyncProcess.checkNonZeroExit(args: fixturePath.appending(components: ".build", UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "Foo").pathString).withSwiftLineEnding
            XCTAssertEqual(output, "Foo\nBar\n")
        }
    }

    func testInternalExecAsDep() async throws {
        try await fixtureXCTest(name: "DependencyResolution/Internal/InternalExecutableAsDependency") { fixturePath in
            await XCTAssertBuildFails(fixturePath, buildSystem: .native)
        }
    }

    func testInternalComplex() async throws {
        try await fixtureXCTest(name: "DependencyResolution/Internal/Complex") { fixturePath in
            await XCTAssertBuilds(fixturePath, buildSystem: .native)

            let output = try await AsyncProcess.checkNonZeroExit(args: fixturePath.appending(components: ".build", UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "Foo").pathString).withSwiftLineEnding
            XCTAssertEqual(output, "meiow Baz\n")
        }
    }

    /// Check resolution of a trivial package with one dependency.
    func testExternalSimple() async throws {
        try await fixtureXCTest(name: "DependencyResolution/External/Simple") { fixturePath in
            // Add several other tags to check version selection.
            let repo = GitRepository(path: fixturePath.appending(components: "Foo"))
            for tag in ["1.1.0", "1.2.0"] {
                try repo.tag(name: tag)
            }

            let packageRoot = fixturePath.appending("Bar")
            await XCTAssertBuilds(packageRoot, buildSystem: .native)
            XCTAssertFileExists(fixturePath.appending(components: "Bar", ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", executableName("Bar")))
            let path = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssert(try GitRepository(path: path).getTags().contains("1.2.3"))
        }
    }

    func testExternalComplex() async throws {
        try await fixtureXCTest(name: "DependencyResolution/External/Complex") { fixturePath in
            await XCTAssertBuilds(fixturePath.appending("app"), buildSystem: .native)
            let output = try await AsyncProcess.checkNonZeroExit(args: fixturePath.appending(components: "app", ".build", UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "Dealer").pathString).withSwiftLineEnding
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }
    
    func testConvenienceBranchInit() async throws {
        try await fixtureXCTest(name: "DependencyResolution/External/Branch") { fixturePath in
            // Tests the convenience init .package(url: , branch: )
            let app = fixturePath.appending("Bar")
            try await executeSwiftBuild(
                app,
                buildSystem: .native,
            )
        }
    }

    func testMirrors() async throws {
        try await fixtureXCTest(name: "DependencyResolution/External/Mirror") { fixturePath in
            let prefix = try resolveSymlinks(fixturePath)
            let appPath = prefix.appending("App")
            let packageResolvedPath = appPath.appending("Package.resolved")

            // prepare the dependencies as git repos
            for directory in ["Foo", "Bar", "BarMirror"] {
                let path = prefix.appending(component: directory)
                _ = try await AsyncProcess.checkNonZeroExit(args: Git.tool, "-C", path.pathString, "init")
                _ = try await AsyncProcess.checkNonZeroExit(args: Git.tool, "-C", path.pathString, "checkout", "-b", "newMain")
            }

            // run with no mirror
            do {
                let output = try await executeSwiftPackage(
                    appPath,
                    extraArgs: ["show-dependencies"],
                    buildSystem: .native,
                )
                // logs are in stderr
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.appending("Foo").pathString)\n"))
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.appending("Bar").pathString)\n"))
                // results are in stdout
                XCTAssertMatch(output.stdout, .contains("foo<\(prefix.appending("Foo").pathString)@unspecified"))
                XCTAssertMatch(output.stdout, .contains("bar<\(prefix.appending("Bar").pathString)@unspecified"))

                let resolvedPackages: String = try localFileSystem.readFileContents(packageResolvedPath)
                XCTAssertMatch(resolvedPackages, .contains(prefix.appending("Foo").escapedPathString))
                XCTAssertMatch(resolvedPackages, .contains(prefix.appending("Bar").escapedPathString))

                await XCTAssertBuilds(appPath, buildSystem: .native)
            }

            // clean
            try localFileSystem.removeFileTree(appPath.appending(".build"))
            try localFileSystem.removeFileTree(packageResolvedPath)

            // set mirror
            _ = try await executeSwiftPackage(
                appPath,
                extraArgs: [
                    "config",
                    "set-mirror",
                    "--original-url",
                    prefix.appending("Bar").pathString,
                    "--mirror-url",
                    prefix.appending("BarMirror").pathString,
                ],
                buildSystem: .native,
            )

            // run with mirror
            do {
                let output = try await executeSwiftPackage(
                    appPath,
                    extraArgs: ["show-dependencies"],
                    buildSystem: .native,
                )
                // logs are in stderr
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.appending("Foo").pathString)\n"))
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.appending("BarMirror").pathString)\n"))
                XCTAssertNoMatch(output.stderr, .contains("Fetching \(prefix.appending("Bar").pathString)\n"))
                // result are in stdout
                XCTAssertMatch(output.stdout, .contains("foo<\(prefix.appending("Foo").pathString)@unspecified"))
                XCTAssertMatch(output.stdout, .contains("barmirror<\(prefix.appending("BarMirror").pathString)@unspecified"))
                XCTAssertNoMatch(output.stdout, .contains("bar<\(prefix.appending("Bar").pathString)@unspecified"))

                // rdar://52529014 mirrors should not be reflected in `Package.resolved` file
                let resolvedPackages: String = try localFileSystem.readFileContents(packageResolvedPath)
                XCTAssertMatch(resolvedPackages, .contains(prefix.appending("Foo").escapedPathString))
                XCTAssertMatch(resolvedPackages, .contains(prefix.appending("Bar").escapedPathString))
                XCTAssertNoMatch(resolvedPackages, .contains(prefix.appending("BarMirror").escapedPathString))

                await XCTAssertBuilds(appPath, buildSystem: .native)
            }
        }
    }

    func testPackageLookupCaseInsensitive() async throws {
        try await fixtureXCTest(name: "DependencyResolution/External/PackageLookupCaseInsensitive") { fixturePath in
            try await executeSwiftPackage(
                fixturePath.appending("pkg"),
                extraArgs: ["update"],
                buildSystem: .native,
            )
        }
    }
}
