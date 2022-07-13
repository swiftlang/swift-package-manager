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

import Basics
import PackageModel
import SPMTestSupport
import TSCBasic
import Xcodeproj
import XCTest

class FunctionalTests: XCTestCase {
    func testSingleModuleLibrary() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "ValidLayouts/SingleModule/Library") { fixturePath in
            XCTAssertXcodeprojGen(fixturePath)
            let pbx = fixturePath.appending(component: "Library.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = AbsolutePath("build/Build/Products/Debug", relativeTo: fixturePath)
            XCTAssertDirectoryExists(build.appending(component: "Library.framework"))
        }
    }

    func testSwiftExecWithCDep() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            // This will also test Modulemap generation for xcodeproj.
            XCTAssertXcodeprojGen(fixturePath)
            let pbx = fixturePath.appending(component: "SwiftCMixed.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            // Ensure we have plist for the library target.
            XCTAssertFileExists(pbx.appending(component: "SeaLib_Info.plist"))

            XCTAssertXcodeBuild(project: pbx)
            let build = AbsolutePath("build/Build/Products/Debug", relativeTo: fixturePath)
            XCTAssertDirectoryExists(build.appending(component: "SeaLib.framework"))
            XCTAssertFileExists(build.appending(component: "SeaExec"))
            XCTAssertFileExists(build.appending(component: "CExec"))
        }
    }

    func testXcodeProjWithPkgConfig() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/PkgConfig") { fixturePath in
            let systemModule = fixturePath.appending(component: "SystemModule")
            // Create a shared library.
            let input = systemModule.appending(components: "Sources", "SystemModule.c")
            let output =  systemModule.appending(component: "libSystemModule.dylib")
            try systemQuietly(["clang", "-shared", input.pathString, "-o", output.pathString])

            let pcFile = fixturePath.appending(component: "libSystemModule.pc")
            try! write(path: pcFile) { stream in
                stream <<< """
                    prefix=\(fixturePath.appending(component: "SystemModule").pathString)
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
            let moduleUser = fixturePath.appending(component: "SystemModuleUser")
            let env = ["PKG_CONFIG_PATH": fixturePath.pathString]
            XCTAssertXcodeprojGen(moduleUser, env: env)
            let pbx = moduleUser.appending(component: "SystemModuleUser.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = AbsolutePath("build/Build/Products/Debug", relativeTo: moduleUser)
            XCTAssertFileExists(build.appending(components: "SystemModuleUser"))
        }
    }

    func testModuleNamesWithNonC99Names() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/PackageWithNonc99NameModules") { fixturePath in
            XCTAssertXcodeprojGen(fixturePath)
            let pbx = fixturePath.appending(component: "PackageWithNonc99NameModules.xcodeproj")
            XCTAssertDirectoryExists(pbx)
            XCTAssertXcodeBuild(project: pbx)
            let build = AbsolutePath("build/Build/Products/Debug", relativeTo: fixturePath)
            XCTAssertDirectoryExists(build.appending(component: "A_B.framework"))
            XCTAssertDirectoryExists(build.appending(component: "B_C.framework"))
            XCTAssertDirectoryExists(build.appending(component: "C_D.framework"))
        }
    }

    func testSystemModule() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        // Because there isn't any one system target that we can depend on for testing purposes, we build our own.
        try write(path: AbsolutePath("/tmp/fake.h")) { stream in
            stream <<< "extern const char GetFakeString(void);\n"
        }
        try write(path: AbsolutePath("/tmp/fake.c")) { stream in
            stream <<< "const char * GetFakeString(void) { return \"abc\"; }\n"
        }
        try TSCBasic.Process.checkNonZeroExit(
            args: "env", "-u", "TOOLCHAINS", "xcrun", "clang", "-dynamiclib", "/tmp/fake.c", "-o", "/tmp/libfake.dylib")
        // Now we use a fixture for both the system library wrapper and the text executable.
        try fixture(name: "Miscellaneous/SystemModules") { fixturePath in
            let fakeDir = fixturePath.appending(component: "CFake")
            XCTAssertDirectoryExists(fakeDir)
            let execDir = fixturePath.appending(component: "TestExec")
            XCTAssertDirectoryExists(execDir)
            XCTAssertXcodeprojGen(execDir, flags: ["-Xlinker", "-L/tmp/"])
            let proj = execDir.appending(component: "TestExec.xcodeproj")
            XCTAssertXcodeBuild(project: proj)
        }
    }
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
        let swiftCompilerPath = UserToolchain.default.swiftCompilerPath

        // Override path to the Swift compiler.
        let stream = BufferedOutputByteStream()
        stream <<< "SWIFT_EXEC = " <<< swiftCompilerPath.pathString <<< "\n"

        // Override Swift library path, if present.
        let swiftLibraryPath = resolveSymlinks(swiftCompilerPath).appending(components: "..", "..", "lib", "swift", "macosx")
        if localFileSystem.exists(swiftCompilerPath) {
            stream <<< "SWIFT_LIBRARY_PATH = " <<< swiftLibraryPath.pathString <<< "\n"
            stream <<< "TOOLCHAIN_DIR = " <<< swiftCompilerPath.appending(components: "..", "..").pathString <<< "\n"
        }

        // We don't need dSYM generated for tests
        stream <<< "DEBUG_INFORMATION_FORMAT = dwarf\n"

        try localFileSystem.writeFileContents(xcconfig, bytes: stream.bytes)

        let packageName = project.basenameWithoutExt
        let scheme = packageName + "-Package"

        let buildDir = project.parentDirectory.appending(component: "build")
        try TSCBasic.Process.checkNonZeroExit(
            args: "xcodebuild",
              "-project", project.pathString,
              "-scheme", scheme,
              "-xcconfig", xcconfig.pathString,
              "-derivedDataPath", buildDir.pathString,
              "-destination", "platform=macOS",
              "COMPILER_INDEX_STORE_ENABLE=NO",
            environment: env)
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

func XCTAssertXcodeprojGen(_ prefix: AbsolutePath, flags: [String] = [], env: EnvironmentVariables? = nil, file: StaticString = #file, line: UInt = #line) {
    do {
        print("    Generating XcodeProject")
        _ = try SwiftPMProduct.SwiftPackage.execute(flags + ["generate-xcodeproj"], packagePath: prefix, env: env)
    } catch {
        XCTFail("`swift package generate-xcodeproj' failed:\n\n\(error)\n", file: file, line: line)
    }
}
