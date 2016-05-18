/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
import Utility
import Xcodeproj

import func POSIX.mkdtemp

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

    func testXcodeProjWithPkgConfig() {
        fixture(name: "Miscellaneous/PkgConfig") { prefix in
            XCTAssertBuilds(prefix, "SystemModule")
            XCTAssertFileExists(prefix, "SystemModule", ".build", "debug", "libSystemModule.so")
            let pcFile = Path.join(prefix, "libSystemModule.pc")
            try! write(path: pcFile) { stream in
                stream <<< "prefix=\(Path.join(prefix, "SystemModule"))\n"
                stream <<< "exec_prefix=${prefix}\n"
                stream <<< "libdir=${exec_prefix}/.build/debug\n"
                stream <<< "includedir=${prefix}/Sources/include\n"

                stream <<< "Name: SystemModule\n"
                stream <<< "URL: http://127.0.0.1/\n"
                stream <<< "Description: The one and only SystemModule\n"
                stream <<< "Version: 1.10.0\n"
                stream <<< "Cflags: -I${includedir}\n"
                stream <<< "Libs: -L${libdir} -lSystemModule\n"
            }
            let moduleUser = Path.join(prefix, "SystemModuleUser")
            let env = ["PKG_CONFIG_PATH": prefix]
            XCTAssertBuilds(moduleUser, env: env)
            XCTAssertXcodeprojGen(moduleUser, env: env)
            let pbx = Path.join(moduleUser, "SystemModuleUser.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            XCTAssertFileExists(moduleUser, "build", "Debug", "SystemModuleUser")
        }
    }

    func testModuleNamesWithNonC99Names() {
        fixture(name: "Miscellaneous/PackageWithNonc99NameModules") { prefix in
            XCTAssertXcodeprojGen(prefix)
            let pbx = Path.join(prefix, "PackageWithNonc99NameModules.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = Path.join(prefix, "build", "Debug")
            XCTAssertFileExists(build, "libA-B.dylib")
            XCTAssertFileExists(build, "libB-C.dylib")
        }
    }
}


extension FunctionalTests {
    static var allTests : [(String, (FunctionalTests) -> () throws -> Void)] {
        return [
            ("testSingleModuleLibrary", testSingleModuleLibrary),
            ("testSwiftExecWithCDep", testSwiftExecWithCDep),
            ("testXcodeProjWithPkgConfig", testXcodeProjWithPkgConfig),
            ("testModuleNamesWithNonC99Names", testModuleNamesWithNonC99Names),
        ]
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

func XCTAssertXcodeprojGen(_ prefix: String, env: [String: String] = [:], file: StaticString = #file, line: UInt = #line) {
    do {
        print("    Generating XcodeProject")
        try executeSwiftBuild(["-X"], chdir: prefix, printIfError: true, env: env)
    } catch {
        XCTFail("`swift build -X' failed:\n\n\(error)\n", file: file, line: line)
    }
}

#endif
