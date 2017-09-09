/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Commands
import TestSupport
import Basic
import Utility
import SourceControl

import func POSIX.rename

class ValidLayoutsTests: XCTestCase {

    func testSingleModuleLibrary() {
        runLayoutFixture(name: "SingleModule/Library") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            XCTAssertFileExists(debugPath.appending(component: "Library.swiftmodule"))
        }
    }

    func testSingleModuleExecutable() {
        runLayoutFixture(name: "SingleModule/Executable") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            XCTAssertFileExists(debugPath.appending(component: "Executable"))
        }
    }

    func testSingleModuleSubfolderWithSwiftSuffix() {
        fixture(name: "ValidLayouts/SingleModule/SubfolderWithSwiftSuffix", file: #file, line: #line) { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            XCTAssertFileExists(debugPath.appending(component: "Bar.swiftmodule"))
        }
    }

    func testMultipleModulesLibraries() {
        runLayoutFixture(name: "MultipleModules/Libraries") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            for x in ["Bar", "Baz", "Foo"] {
                XCTAssertFileExists(debugPath.appending(component: "\(x).swiftmodule"))
            }
        }
    }

    func testMultipleModulesExecutables() {
        runLayoutFixture(name: "MultipleModules/Executables") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            for x in ["Bar", "Baz", "Foo"] {
                let output = try Process.checkNonZeroExit(args: debugPath.appending(component: x).asString)
                XCTAssertEqual(output, "\(x)\n")
            }
        }
    }

    func testMadeValidWithExclude() {
        fixture(name: "ValidLayouts/MadeValidWithExclude/Case1") { prefix in
            XCTAssertBuilds(prefix)
        }
        fixture(name: "ValidLayouts/MadeValidWithExclude/Case2") { prefix in
            XCTAssertBuilds(prefix)
        }
    }

    func testExtraCommandLineFlags() {
        fixture(name: "ValidLayouts/ExtraCommandLineFlags") { prefix in
            // This project is expected to require Xcc and Xswiftc overrides.
            XCTAssertBuildFails(prefix)
            XCTAssertBuildFails(prefix, Xcc: ["-DEXTRA_C_DEFINE=2"])
            XCTAssertBuilds(prefix, Xcc: ["-DEXTRA_C_DEFINE=2"], Xswiftc: ["-DEXTRA_SWIFTC_DEFINE"])
        }
    }

    static var allTests = [
        ("testSingleModuleLibrary", testSingleModuleLibrary),
        ("testSingleModuleExecutable", testSingleModuleExecutable),
        ("testSingleModuleSubfolderWithSwiftSuffix", testSingleModuleSubfolderWithSwiftSuffix),
        ("testMultipleModulesLibraries", testMultipleModulesLibraries),
        ("testMultipleModulesExecutables", testMultipleModulesExecutables),
        ("testMadeValidWithExclude", testMadeValidWithExclude),
        ("testExtraCommandLineFlags", testExtraCommandLineFlags),
    ]
}


// MARK: Utility

extension ValidLayoutsTests {
    func runLayoutFixture(name: String, line: UInt = #line, body: (AbsolutePath) throws -> Void) {
        let name = "ValidLayouts/\(name)"

        // 1. Rooted layout
        fixture(name: name, file: #file, line: line, body: body)

        // 2. Move everything to a directory called "Sources"
        fixture(name: name, file: #file, line: line) { prefix in
            let files = try! localFileSystem.getDirectoryContents(prefix).filter{ $0 != "Package.swift" }
            let dir = prefix.appending(component: "Sources")
            try makeDirectories(dir)
            for file in files {
                try rename(old: prefix.appending(component: file).asString, new: dir.appending(component: file).asString)
            }
            try body(prefix)
        }

        // 3. Symlink some other directory to a directory called "Sources"
        fixture(name: name, file: #file, line: line) { prefix in
            let files = try! localFileSystem.getDirectoryContents(prefix).filter{ $0 != "Package.swift" }
            let dir = prefix.appending(component: "Floobles")
            try makeDirectories(dir)
            for file in files {
                try rename(old: prefix.appending(component: file).asString, new: dir.appending(component: file).asString)
            }
            try createSymlink(prefix.appending(component: "Sources"), pointingAt: dir, relative: true)
            try body(prefix)
        }
    }
}
