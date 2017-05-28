/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

import TestSupport
import SourceControl

class DependencyResolutionTests: XCTestCase {
    func testInternalSimple() {
        fixture(name: "DependencyResolution/Internal/Simple") { prefix in
            XCTAssertBuilds(prefix)

            let output = try Process.checkNonZeroExit(args: prefix.appending(components: ".build", "debug", "Foo").asString)
            XCTAssertEqual(output, "Foo\nBar\n")
        }
    }

    func testInternalExecAsDep() {
        fixture(name: "DependencyResolution/Internal/InternalExecutableAsDependency") { prefix in
            XCTAssertBuildFails(prefix)
        }
    }

    func testInternalComplex() {
        fixture(name: "DependencyResolution/Internal/Complex") { prefix in
            XCTAssertBuilds(prefix)

            let output = try Process.checkNonZeroExit(args: prefix.appending(components: ".build", "debug", "Foo").asString)
            XCTAssertEqual(output, "meiow Baz\n")
        }
    }

    /// Check resolution of a trivial package with one dependency.
    func testExternalSimple() {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            // Add several other tags to check version selection.
            let repo = GitRepository(path: prefix.appending(components: "Foo"))
            for tag in ["1.1.0", "1.2.0"] {
                try repo.tag(name: tag)
            }

            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(prefix.appending(components: "Bar", ".build", "debug", "Bar"))
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssert(GitRepository(path: path).tags.contains("1.2.3"))
        }
    }

    func testExternalComplex() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertBuilds(prefix.appending(component: "app"))
            let output = try Process.checkNonZeroExit(args: prefix.appending(components: "app", ".build", "debug", "Dealer").asString)
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }

    func testIndirectTestsDontBuild() {
        fixture(name: "DependencyResolution/External/IgnoreIndirectTests") { prefix in
            XCTAssertBuilds(prefix.appending(component: "app"))
        }
    }

    static var allTests = [
        ("testInternalSimple", testInternalSimple),
        ("testInternalExecAsDep", testInternalExecAsDep),
        ("testInternalComplex", testInternalComplex),
        ("testExternalSimple", testExternalSimple),
        ("testExternalComplex", testExternalComplex),
        ("testIndirectTestsDontBuild", testIndirectTestsDontBuild),
    ]
}
