/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Commands
import TestSupport
import Basic
import Utility

class ModuleMapsTestCase: XCTestCase {

    private func fixture(name: String, cModuleName: String, rootpkg: String, body: @escaping (AbsolutePath, [String]) throws -> Void) {
        TestSupport.fixture(name: name) { prefix in
            let input = prefix.appending(components: cModuleName, "C", "foo.c")
            let outdir = prefix.appending(components: rootpkg, ".build", Destination.host.target, "debug")
            try makeDirectories(outdir)
            let output = outdir.appending(component: "libfoo.\(Destination.host.dynamicLibraryExtension)")
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

            XCTAssertBuilds(prefix.appending(component: "App"), Xld: Xld)

            let targetPath = prefix.appending(components: "App", ".build", Destination.host.target)
            let debugout = try Process.checkNonZeroExit(args: targetPath.appending(components: "debug", "App").asString)
            XCTAssertEqual(debugout, "123\n")
            let releaseout = try Process.checkNonZeroExit(args: targetPath.appending(components: "release", "App").asString)
            XCTAssertEqual(releaseout, "123\n")
        }
    }

    func testTransitiveDependency() {
        fixture(name: "ModuleMaps/Transitive", cModuleName: "packageD", rootpkg: "packageA") { prefix, Xld in

            XCTAssertBuilds(prefix.appending(component: "packageA"), Xld: Xld)

            func verify(_ conf: String, file: StaticString = #file, line: UInt = #line) throws {
                let out = try Process.checkNonZeroExit(args: prefix.appending(components: "packageA", ".build", Destination.host.target, conf, "packageA").asString)
                XCTAssertEqual(out, """
                    calling Y.bar()
                    Y.bar() called
                    X.foo() called
                    123
                    
                    """)
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
