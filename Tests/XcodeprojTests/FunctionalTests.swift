/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Commands
import TestSupport
import PackageModel
import Utility
import Xcodeproj

class FunctionalTests: XCTestCase {
    func testSingleModuleLibrary() {
#if os(macOS)
        fixture(name: "ValidLayouts/SingleModule/Library") { prefix in
            XCTAssertXcodeprojGen(prefix)
            let pbx = prefix.appending(component: "Library.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = prefix.appending(components: "build", "Debug")
            XCTAssertDirectoryExists(build.appending(component: "Library.framework"))
        }
#endif
    }

    func testSwiftExecWithCDep() {
#if os(macOS)
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            // This will also test Modulemap generation for xcodeproj.
            XCTAssertXcodeprojGen(prefix)
            let pbx = prefix.appending(component: "SwiftCMixed.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            // Ensure we have plist for the library target.
            XCTAssertFileExists(pbx.appending(component: "SeaLib_Info.plist"))

            XCTAssertXcodeBuild(project: pbx)
            let build = prefix.appending(components: "build", "Debug")
            XCTAssertDirectoryExists(build.appending(component: "SeaLib.framework"))
            XCTAssertFileExists(build.appending(component: "SeaExec"))
            XCTAssertFileExists(build.appending(component: "CExec"))
        }
#endif
    }

    func testXcodeProjWithPkgConfig() {
#if os(macOS)
        fixture(name: "Miscellaneous/PkgConfig") { prefix in
            let systemModule = prefix.appending(component: "SystemModule")
            // Create a shared library.
            let input = systemModule.appending(components: "Sources", "SystemModule.c")
            let output =  systemModule.appending(component: "libSystemModule.dylib")
            try systemQuietly(["clang", "-shared", input.asString, "-o", output.asString])

            let pcFile = prefix.appending(component: "libSystemModule.pc")
            try! write(path: pcFile) { stream in
                stream <<< """
                    prefix=\(prefix.appending(component: "SystemModule").asString)
                    exec_prefix=${prefix}
                    libdir=${exec_prefix}
                    includedir=${prefix}/Sources/include
                    Name: SystemModule
                    URL: http://127.0.0.1/
                    Description: The one and only SystemModule
                    Version: 1.10.0
                    Cflags: -I${includedir}
                    Libs: -L${libdir} -lSystemModule
                    """
            }
            let moduleUser = prefix.appending(component: "SystemModuleUser")
            let env = ["PKG_CONFIG_PATH": prefix.asString]
            XCTAssertBuilds(moduleUser, env: env)
            XCTAssertXcodeprojGen(moduleUser, env: env)
            let pbx = moduleUser.appending(component: "SystemModuleUser.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            XCTAssertFileExists(moduleUser.appending(components: "build", "Debug", "SystemModuleUser"))
        }
#endif
    }

    func testModuleNamesWithNonC99Names() {
#if os(macOS)
        fixture(name: "Miscellaneous/PackageWithNonc99NameModules") { prefix in
            XCTAssertXcodeprojGen(prefix)
            let pbx = prefix.appending(component: "PackageWithNonc99NameModules.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = prefix.appending(components: "build", "Debug")
            XCTAssertDirectoryExists(build.appending(component: "A_B.framework"))
            XCTAssertDirectoryExists(build.appending(component: "B_C.framework"))
            XCTAssertDirectoryExists(build.appending(component: "C_D.framework"))
        }
#endif
    }
    
    func testSystemModule() {
#if os(macOS)
        // Because there isn't any one system target that we can depend on for testing purposes, we build our own.
        try! write(path: AbsolutePath("/tmp/fake.h")) { stream in
            stream <<< "extern const char GetFakeString(void);\n"
        }
        try! write(path: AbsolutePath("/tmp/fake.c")) { stream in
            stream <<< "const char * GetFakeString(void) { return \"abc\"; }\n"
        }
        try! Process.checkNonZeroExit(
            args: "env", "-u", "TOOLCHAINS", "xcrun", "clang", "-dynamiclib", "/tmp/fake.c", "-o", "/tmp/libfake.dylib")
        // Now we use a fixture for both the system library wrapper and the text executable.
        fixture(name: "Miscellaneous/SystemModules") { prefix in
            XCTAssertBuilds(prefix.appending(component: "TestExec"), Xld: ["-L/tmp/"])
            XCTAssertFileExists(prefix.appending(components: "TestExec", ".build", Destination.host.target, "debug", "TestExec"))
            let fakeDir = prefix.appending(component: "CFake")
            XCTAssertDirectoryExists(fakeDir)
            let execDir = prefix.appending(component: "TestExec")
            XCTAssertDirectoryExists(execDir)
            XCTAssertXcodeprojGen(execDir, flags: ["-Xlinker", "-L/tmp/"])
            let proj = execDir.appending(component: "TestExec.xcodeproj")
            XCTAssertXcodeBuild(project: proj)
        }
#endif
    }

    static var allTests = [
        ("testSingleModuleLibrary", testSingleModuleLibrary),
        ("testSwiftExecWithCDep", testSwiftExecWithCDep),
        ("testXcodeProjWithPkgConfig", testXcodeProjWithPkgConfig),
        ("testModuleNamesWithNonC99Names", testModuleNamesWithNonC99Names),
        ("testSystemModule", testSystemModule),
    ]
}

func write(path: AbsolutePath, write: (OutputByteStream) -> Void) throws {
    let stream = BufferedOutputByteStream()
    write(stream)
    try localFileSystem.writeFileContents(path, bytes: stream.bytes)
}

func XCTAssertXcodeBuild(project: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    do {
        var env = ProcessInfo.processInfo.environment
        // Use the default toolchain if its not explicitly set.
        if env["TOOLCHAINS"] == nil {
            env["TOOLCHAINS"] = "default"
        }
        let xcconfig = project.appending(component: "overrides.xcconfig")
        let swiftCompilerPath = Resources.default.swiftCompiler.asString
        try localFileSystem.writeFileContents(xcconfig) {
            $0 <<< "SWIFT_EXEC = " <<< swiftCompilerPath
        }
        try Process.checkNonZeroExit(
            args: "xcodebuild", "-project", project.asString, "-alltargets", "-xcconfig", xcconfig.asString, environment: env)
    } catch {
        XCTFail("xcodebuild failed:\n\n\(error)\n", file: file, line: line)
        switch error {
        case ProcessResult.Error.nonZeroExit(let result):
            try? print("stdout: " + result.utf8Output())
            try? print("stderr: " + result.utf8stderrOutput())
        default:
            break
        }
    }
}

func XCTAssertXcodeprojGen(_ prefix: AbsolutePath, flags: [String] = [], env: [String: String]? = nil, file: StaticString = #file, line: UInt = #line) {
    do {
        print("    Generating XcodeProject")
        _ = try SwiftPMProduct.SwiftPackage.execute(flags + ["generate-xcodeproj"], packagePath: prefix, env: env, printIfError: true)
    } catch {
        XCTFail("`swift package generate-xcodeproj' failed:\n\n\(error)\n", file: file, line: line)
    }
}
