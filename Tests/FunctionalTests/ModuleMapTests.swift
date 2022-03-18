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
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

class ModuleMapsTestCase: XCTestCase {

    private func fixture(name: String, cModuleName: String, rootpkg: String, body: @escaping (AbsolutePath, [String]) throws -> Void) throws {
        try SPMTestSupport.fixture(name: name) { fixturePath in
            let input = fixturePath.appending(components: cModuleName, "C", "foo.c")
            let triple = UserToolchain.default.triple
            let outdir = fixturePath.appending(components: rootpkg, ".build", triple.platformBuildPathComponent(), "debug")
            try makeDirectories(outdir)
            let output = outdir.appending(component: "libfoo\(triple.dynamicLibraryExtension)")
            try systemQuietly(["clang", "-shared", input.pathString, "-o", output.pathString])

            var Xld = ["-L", outdir.pathString]
        #if os(Linux) || os(Android)
            Xld += ["-rpath", outdir.pathString]
        #endif

            try body(fixturePath, Xld)
        }
    }

    func testDirectDependency() throws {
        try fixture(name: "ModuleMaps/Direct", cModuleName: "CFoo", rootpkg: "App") { fixturePath, Xld in

            XCTAssertBuilds(fixturePath.appending(component: "App"), Xld: Xld)

            let triple = UserToolchain.default.triple
            let targetPath = fixturePath.appending(components: "App", ".build", triple.platformBuildPathComponent())
            let debugout = try Process.checkNonZeroExit(args: targetPath.appending(components: "debug", "App").pathString)
            XCTAssertEqual(debugout, "123\n")
            let releaseout = try Process.checkNonZeroExit(args: targetPath.appending(components: "release", "App").pathString)
            XCTAssertEqual(releaseout, "123\n")
        }
    }

    func testTransitiveDependency() throws {
        try fixture(name: "ModuleMaps/Transitive", cModuleName: "packageD", rootpkg: "packageA") { fixturePath, Xld in

            XCTAssertBuilds(fixturePath.appending(component: "packageA"), Xld: Xld)

            func verify(_ conf: String) throws {
                let triple = UserToolchain.default.triple
                let out = try Process.checkNonZeroExit(args: fixturePath.appending(components: "packageA", ".build", triple.platformBuildPathComponent(), conf, "packageA").pathString)
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
}
