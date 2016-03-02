/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.mkdir
import func POSIX.popen
import Utility
import XCTest

#if os(OSX)
private let dylib = "dylib"
#else
private let dylib = "so"
#endif

class ModuleMapsTestCase: XCTestCase {

    private func fixture(name name: String, CModuleName: String, rootpkg: String, body: (String, [String]) throws -> Void) {
        Functionaltest.fixture(name: name) { prefix in
            let input = Path.join(prefix, CModuleName, "C/foo.c")
            let outdir = try mkdir(prefix, rootpkg, ".build/debug")
            let output = Path.join(outdir, "libfoo.\(dylib)")
            try popen(["clang", "-shared", input, "-o", output])

            var Xld = ["-L", outdir]
        #if os(Linux)
            Xld += ["-rpath", outdir]
        #endif

            try body(prefix, Xld)
        }
    }

    func testDirectDependency() {
        fixture(name: "ModuleMaps/Direct", CModuleName: "CFoo", rootpkg: "App") { prefix, Xld in

            XCTAssertBuilds(prefix, "App", Xld: Xld)

            let debugout = try popen([Path.join(prefix, "App/.build/debug/App")])
            XCTAssertEqual(debugout, "123\n")
            let releaseout = try popen([Path.join(prefix, "App/.build/release/App")])
            XCTAssertEqual(releaseout, "123\n")
        }
    }

    func testTransitiveDependency() {
        fixture(name: "ModuleMaps/Transitive", CModuleName: "packageD", rootpkg: "packageA") { prefix, Xld in

            XCTAssertBuilds(prefix, "packageA", Xld: Xld)

            func verify(conf: String, file: StaticString = #file, line: UInt = #line) {
                do {
                    let expectedOutput = "calling Y.bar()\nY.bar() called\nX.foo() called\n123\n"
                    let out = try popen([Path.join(prefix, "packageA/.build", conf, "packageA")])
                    XCTAssertEqual(out, expectedOutput)
                } catch {
                    XCTFail("\(error)", file: file, line: line)
                }
            }

            verify("debug")
            verify("release")
        }
    }
}
