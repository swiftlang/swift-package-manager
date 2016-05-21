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
            XCTAssertDirectoryExists(build, "Library.framework")
        }
    }

    func testSwiftExecWithCDep() {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            // FIXME: Temporarily manually create the module map until we fix SR-1450
            let seaLibModuleMap = Path.join(prefix, "Sources/SeaLib/include", "module.modulemap")
            try! write(path: seaLibModuleMap) { stream in
                stream <<< "module SeaLib {"
                stream <<< "    umbrella \".\""
                stream <<< "    export *"
                stream <<< "}"
            }
            XCTAssertXcodeprojGen(prefix)
            let pbx = Path.join(prefix, "SwiftCMixed.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = Path.join(prefix, "build", "Debug")
            XCTAssertDirectoryExists(build, "SeaLib.framework")
            XCTAssertFileExists(build, "SeaExec")
        }
    }

    func testXcodeProjWithPkgConfig() {
        fixture(name: "Miscellaneous/PkgConfig") { prefix in
            XCTAssertBuilds(prefix, "SystemModule")
            XCTAssertFileExists(prefix, "SystemModule", ".build", "debug", "SystemModule".soname)
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
            XCTAssertDirectoryExists(build, "A_B.framework")
            XCTAssertDirectoryExists(build, "B_C.framework")
        }
    }
    
    func testSystemModule() {
        // Because there isn't any one system module that we can depend on for testing purposes, we build our own.
        try! write(path: "/tmp/fake.h") { stream in
            stream <<< "extern const char GetFakeString(void);\n"
        }
        try! write(path: "/tmp/fake.c") { stream in
            stream <<< "const char * GetFakeString(void) { return \"abc\"; }\n"
        }
        var out = ""
        do {
            try popen(["env", "-u", "TOOLCHAINS", "xcrun", "clang", "-dynamiclib", "/tmp/fake.c", "-o", "/tmp/libfake.dylib"], redirectStandardError: true) {
                out += $0
            }
        } catch {
            print("output:", out)
            XCTFail("Failed to create test library:\n\n\(error)\n")
        }
        // Now we use a fixture for both the system library wrapper and the text executable.
        fixture(name: "Miscellaneous/SystemModules") { prefix in
            XCTAssertBuilds(prefix, "TestExec", Xld: ["-L/tmp/"])
            XCTAssertFileExists(prefix, "TestExec", ".build", "debug", "TestExec")
            let fakeDir = Path.join(prefix, "CFake")
            XCTAssertDirectoryExists(fakeDir)
            let execDir = Path.join(prefix, "TestExec")
            XCTAssertDirectoryExists(execDir)
            XCTAssertXcodeprojGen(execDir, flags: ["-Xlinker", "-L/tmp/"])
            let proj = Path.join(execDir, "TestExec.xcodeproj")
            XCTAssertXcodeBuild(project: proj)
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

func write(path: String, write: (OutputByteStream) -> Void) throws {
    try fopen(path, mode: .write) { fp in
        let stream = OutputByteStream()
        write(stream)
        try fputs(stream.bytes.contents, fp)
    }
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

func XCTAssertXcodeprojGen(_ prefix: String, flags: [String] = [], env: [String: String] = [:], file: StaticString = #file, line: UInt = #line) {
    do {
        print("    Generating XcodeProject")
        _ = try SwiftPMProduct.SwiftPackage.execute(["generate-xcodeproj"] + flags, chdir: prefix, env: env, printIfError: true)
    } catch {
        XCTFail("`swift package generate-xcodeproj' failed:\n\n\(error)\n", file: file, line: line)
    }
}

#endif
