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

import XCTest
import SPMTestSupport

import TSCBasic

class ResourcesTests: XCTestCase {
    func testSimpleResources() throws {
        try fixture(name: "Resources/Simple") { fixturePath in
            var executables = ["SwiftyResource"]

            // Objective-C module requires macOS
            #if os(macOS)
            executables.append("SeaResource")
            executables.append("CPPResource")
            #endif

            for execName in executables {
                let (output, _) = try executeSwiftRun(fixturePath, execName)
                XCTAssertTrue(output.contains("foo"), output)
            }
        }
    }

    func testLocalizedResources() throws {
        try fixture(name: "Resources/Localized") { fixturePath in
            try executeSwiftBuild(fixturePath)

            let exec = AbsolutePath(path: ".build/debug/exe", relativeTo: fixturePath)
            // Note: <rdar://problem/59738569> Source from LANG and -AppleLanguages on command line for Linux resources
            let output = try Process.checkNonZeroExit(args: exec.pathString, "-AppleLanguages", "(en_US)")
            XCTAssertEqual(output, """
                ¡Hola Mundo!
                Hallo Welt!
                Bonjour le monde !

                """)
        }
    }

    func testMovedBinaryResources() throws {
        try fixture(name: "Resources/Moved") { fixturePath in
            var executables = ["SwiftyResource"]

            // Objective-C module requires macOS
            #if os(macOS)
            executables.append("SeaResource")
            #endif

            let binPath = try AbsolutePath(validating:
                executeSwiftBuild(fixturePath, configuration: .Release, extraArgs: ["--show-bin-path"]).stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )

            for execName in executables {
                _ = try executeSwiftBuild(fixturePath, configuration: .Release, extraArgs: ["--product", execName])

                try withTemporaryDirectory(prefix: execName) { tmpDirPath in
                    defer {
                        // Unblock and remove the tmp dir on deinit.
                        try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                        try? localFileSystem.removeFileTree(tmpDirPath)
                    }

                    let destBinPath = tmpDirPath.appending(component: execName)
                    // Move the binary
                    try localFileSystem.move(from: binPath.appending(component: execName), to: destBinPath)
                    // Move the resources
                    try localFileSystem
                        .getDirectoryContents(binPath)
                        .filter { $0.contains(execName) && $0.hasSuffix(".bundle") || $0.hasSuffix(".resources") }
                        .forEach { try localFileSystem.move(from: binPath.appending(component: $0), to: tmpDirPath.appending(component: $0)) }
                    // Run the binary
                    let output = try Process.checkNonZeroExit(args: destBinPath.pathString)
                    XCTAssertTrue(output.contains("foo"))
                }
            }
        }
    }

    func testFoundationlessClient() throws {
        try fixture(name: "Resources/FoundationlessClient") { fixturePath in
            #if os(Linux) && swift(>=5.8)
            let pkgPath = fixturePath.appending(components: "AppPkg")
            guard let failure = XCTAssertBuildFails(pkgPath) else {
                XCTFail("missing expected command execution error")
                return
            }
            // Check that the following code expectedly doesn't compile for lack of 'import Foundation'
            XCTAssertMatch(failure.stdout, .contains("print(FooUtils.foo.trimmingCharacters(in: .whitespaces))"))
            #endif
        }
    }

    func testResourceBundleInClangPackageWhenRunningSwiftTest() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try fixture(name: "Resources/Simple") { fixturePath in
            XCTAssertSwiftTest(fixturePath, extraArgs: ["--filter", "ClangResourceTests"])
        }
    }
}
