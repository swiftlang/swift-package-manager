/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import func POSIX.popen

class DependencyResolutionTestCase: XCTestCase {

    func testInternalSimple() {
        fixture(name: "DependencyResolution/Internal/Simple") { prefix in
            XCTAssertBuilds(prefix)

            let output = try popen(["\(prefix)/.build/debug/Foo"])
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

            let output = try popen(["\(prefix)/.build/debug/Foo"])
            XCTAssertEqual(output, "meiow Baz\n")
        }
    }

    func testExternalSimple() {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            XCTAssertBuilds(prefix, "Bar")
            XCTAssertFileExists(prefix, "Bar/.build/debug/Bar")
            XCTAssertDirectoryExists(prefix, "Bar/Packages/Foo-1.2.3")
        }
    }

    func testExternalComplex() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertBuilds(prefix, "app")
            let output = try POSIX.popen(["\(prefix)/app/.build/debug/Dealer"])
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }

    func testIndirectTestsDontBuild() {
        fixture(name: "DependencyResolution/External/IgnoreIndirectTests") { prefix in
            XCTAssertBuilds(prefix, "app")
        }
    }
}
