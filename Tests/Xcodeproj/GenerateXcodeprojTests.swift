/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import func POSIX.mkdtemp
import PackageType
import Xcodeproj
import Utility
import XCTest


// copy pasta
func mktmpdir(_ file: StaticString = #file, line: UInt = #line, @noescape body: (String) throws -> Void) {
    do {
        try POSIX.mkdtemp("spm-tests") { dir in
            defer { _ = try? rmtree(dir) }
            try body(dir)
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func XCTAssertDirectoryExists(_ paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if !path.isDirectory {
        XCTFail("Expected directory doesn’t exist: \(path)", file: file, line: line)
    }
}


#if os(OSX)
class TestGeneration: XCTestCase {

    /// --> this comment is here <--

    func testXcodeBuildCanParseIt() {
        mktmpdir { dstdir in
            func dummy() throws -> [XcodeModuleProtocol] {
                return [try SwiftModule(name: "DummyModuleName", sources: Sources(paths: [], root: dstdir))]
            }

            let projectName = "DummyProjectName"
            let srcroot = dstdir
            let modules = try dummy()
            let products: [Product] = []

            let outpath = try Xcodeproj.generate(dstdir: dstdir, projectName: projectName, srcroot: srcroot, modules: modules, externalModules: [], products: products, options: ([], [], []))

            XCTAssertDirectoryExists(outpath)
            XCTAssertEqual(outpath, Path.join(dstdir, "\(projectName).xcodeproj"))

            let output = try popen(["xcodebuild", "-list", "-project", outpath])

            let expectedOutput = "Information about project \"DummyProjectName\":\n    Targets:\n        DummyModuleName\n\n    Build Configurations:\n        Debug\n        Release\n\n    If no build configuration is specified and -scheme is not passed then \"Debug\" is used.\n\n    Schemes:\n        DummyProjectName\n"

            XCTAssertEqual(output, expectedOutput)
        }
    }
}
#endif
