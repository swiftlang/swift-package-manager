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
    func testDirectDependency() {
        fixture(name: "ModuleMaps/Direct") { prefix in
            let input = Path.join(prefix, "CFoo/C/foo.c")
            let outdir = try mkdir(prefix, "App/.build/debug")
            let output = Path.join(outdir, "libfoo.\(dylib)")
            try popen(["clang", "-dynamiclib", input, "-o", output])

            XCTAssertBuilds(prefix, "App", Xld: ["-L", outdir])

            let debugout = try popen([Path.join(outdir, "App")])
            XCTAssertEqual(debugout, "123\n")
            let releaseout = try popen([Path.join(outdir, "../Release/App")])
            XCTAssertEqual(releaseout, "123\n")
        }
    }
}
