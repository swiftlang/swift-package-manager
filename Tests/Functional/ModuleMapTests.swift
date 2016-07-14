/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility

import func POSIX.popen

#if os(macOS)
private let dylib = "dylib"
#else
private let dylib = "so"
#endif

class ModuleMapsTestCase: XCTestCase {

    private func fixture(name: RelativePath, cModuleName: String, rootpkg: String, body: (AbsolutePath, [String]) throws -> Void) {
        FunctionalTestSuite.fixture(name: name) { prefix in
            let input = prefix.appending(cModuleName).appending("C").appending("foo.c")
            let outdir = prefix.appending(rootpkg).appending(".build/debug")
            try Utility.makeDirectories(outdir.asString)
            let output = outdir.appending("libfoo.\(dylib)")
            try systemQuietly(["clang", "-shared", input.asString, "-o", output.asString])

            var Xld = ["-L", outdir.asString]
        #if os(Linux)
            Xld += ["-rpath", outdir.asString]
        #endif

            try body(prefix, Xld)
        }
    }

    func testDirectDependency() {
        fixture(name: "ModuleMaps/Direct", cModuleName: "CFoo", rootpkg: "App") { prefix, Xld in

            XCTAssertBuilds(prefix.appending("App"), Xld: Xld)

            let debugout = try popen([prefix.appending("App/.build/debug/App").asString])
            XCTAssertEqual(debugout, "123\n")
            let releaseout = try popen([prefix.appending("App/.build/release/App").asString])
            XCTAssertEqual(releaseout, "123\n")
        }
    }

    func testTransitiveDependency() {
        fixture(name: "ModuleMaps/Transitive", cModuleName: "packageD", rootpkg: "packageA") { prefix, Xld in

            XCTAssertBuilds(prefix.appending("packageA"), Xld: Xld)

            func verify(_ conf: String, file: StaticString = #file, line: UInt = #line) throws {
                let expectedOutput = "calling Y.bar()\nY.bar() called\nX.foo() called\n123\n"
                let out = try popen([prefix.appending("packageA").appending(".build").appending(conf).appending("packageA").asString])
                XCTAssertEqual(out, expectedOutput)
            }

            try verify("debug")
            try verify("release")
        }
    }

    static var allTests = [
        ("testDirectDependency", testDirectDependency),
        ("testTransitiveDependency", testTransitiveDependency),
    ]
}
