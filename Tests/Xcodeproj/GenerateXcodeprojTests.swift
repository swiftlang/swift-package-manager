/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Xcodeproj
import Utility
import XCTest

#if os(OSX)

class GenerateXcodeprojTests: XCTestCase {
    func testXcodeBuildCanParseIt() {
        mktmpdir { dstdir in
            func dummy() throws -> [XcodeModuleProtocol] {
                return [try SwiftModule(name: "DummyModuleName", sources: Sources(paths: [], root: dstdir))]
            }

            let projectName = "DummyProjectName"
            let srcroot = dstdir
            let modules = try dummy()
            let products: [Product] = []

            struct Options: XcodeprojOptions {
                let Xcc = [String]()
                let Xld = [String]()
                let Xswiftc = [String]()
                let xcconfigOverrides: AbsolutePath? = nil
            }
            let outpath = try Xcodeproj.generate(dstdir: dstdir, projectName: projectName, srcroot: srcroot, modules: modules, externalModules: [], products: products, options: Options())

            XCTAssertDirectoryExists(outpath)
            XCTAssertEqual(outpath, dstdir.appending(projectName + ".xcodeproj"))

            // We can only validate this on OS X.
            // Don't allow TOOLCHAINS to be overriden here, as it breaks the test below.
            let output = try popen(["env", "-u", "TOOLCHAINS", "xcodebuild", "-list", "-project", outpath.asString]).chomp()

            let expectedOutput = "Information about project \"DummyProjectName\":\n    Targets:\n        DummyModuleName\n\n    Build Configurations:\n        Debug\n        Release\n\n    If no build configuration is specified and -scheme is not passed then \"Debug\" is used.\n\n    Schemes:\n        DummyProjectName\n".chomp()

            XCTAssertEqual(output, expectedOutput)
        }
    }
}

#endif
