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

#if os(OSX)
class FunctionalTests: XCTestCase {
    func testSingleModuleLibrary() {
        fixture(name: "ValidLayouts/SingleModule/Library") { prefix in
            XCTAssertXcodeprojGen(prefix)
            let pbx = Path.join(prefix, "Library.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = Path.join(prefix, "build", "Debug")
            XCTAssertDirectoryExists(build, "Library.swiftmodule")
            XCTAssertFileExists(build, "libLibrary.dylib")
        }
    }

    func testSwiftExecWithCDep() {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            // FIXME: Temporarily manually create the module map until we fix SR-1450
            let seaLibModuleMap = Path.join(prefix, "Sources/SeaLib/include", "module.modulemap")
            try! write(path: seaLibModuleMap) { stream in
                stream <<< "module SeaLib {"
                stream <<< "    umbrella \".\""
                stream <<< "    link \"SeaLib\""
                stream <<< "    export *"
                stream <<< "}"
            }
            XCTAssertXcodeprojGen(prefix)
            let pbx = Path.join(prefix, "SwiftCMixed.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = Path.join(prefix, "build", "Debug")
            XCTAssertDirectoryExists(build, "SeaExec.swiftmodule")
            XCTAssertFileExists(build, "SeaExec")
            XCTAssertFileExists(build, "libSeaLib.dylib")
        }
    }
}

func write(path: String, write: (OutputByteStream) -> Void) throws -> String {
    try fopen(path, mode: .Write) { fp in
        let stream = OutputByteStream()
        write(stream)
        try fputs(stream.bytes.bytes, fp)
    }
    return path
}

func XCTAssertXcodeBuild(project: String, file: StaticString = #file, line: UInt = #line) {
    var out = ""
    do {
        try popen(["env", "-u", "TOOLCHAINS", "xcodebuild", "-project", project], redirectStandardError: true) {
            out += $0
        }
    } catch {
        print("output:", out)
        XCTFail("xcodebuild failed:\n\n\(error)\n", file: file, line: line)
    }
}

func XCTAssertXcodeprojGen(_ prefix: String, file: StaticString = #file, line: UInt = #line) {
    do {
        print("    Generating XcodeProject")
        try executeSwiftBuild(["-X"], chdir: prefix, printIfError: true)
    } catch {
        XCTFail("`swift build -X' failed:\n\n\(error)\n", file: file, line: line)
    }
}

#endif
