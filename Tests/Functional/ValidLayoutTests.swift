/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility

import func POSIX.symlink
import func POSIX.rename
import func POSIX.popen

class ValidLayoutsTestCase: XCTestCase {

    func testSingleModuleLibrary() {
        runLayoutFixture(name: "SingleModule/Library") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("Library.swiftmodule"))
        }
    }

    func testSingleModuleExecutable() {
        runLayoutFixture(name: "SingleModule/Executable") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("Executable"))
        }
    }

    func testSingleModuleCustomizedName() {

        // Package.swift for a single module with a customized name
        // names that target after the package name

        runLayoutFixture(name: "SingleModule/CustomizedName") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("Bar.swiftmodule"))
        }
    }

    func testSingleModuleSubfolderWithSwiftSuffix() {
        fixture(name: "ValidLayouts/SingleModule/SubfolderWithSwiftSuffix", file: #file, line: #line) { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("Bar.swiftmodule"))
        }
    }

    func testMultipleModulesLibraries() {
        runLayoutFixture(name: "MultipleModules/Libraries") { prefix in
            XCTAssertBuilds(prefix)
            for x in ["Bar", "Baz", "Foo"] {
                XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("\(x).swiftmodule"))
            }
        }
    }

    func testMultipleModulesExecutables() {
        runLayoutFixture(name: "MultipleModules/Executables") { prefix in
            XCTAssertBuilds(prefix)
            for x in ["Bar", "Baz", "Foo"] {
                let output = try popen([prefix.appending(".build").appending("debug").appending(x).asString])
                XCTAssertEqual(output, "\(x)\n")
            }
        }
    }

    func testPackageIdentifiers() {
        #if os(macOS)
            // this because sort orders vary on Linux on Mac currently
            let tags = ["1.3.4-alpha.beta.gamma1", "1.2.3+24", "1.2.3", "1.2.3-beta5"]
        #else
            let tags = ["1.2.3", "1.2.3-beta5", "1.3.4-alpha.beta.gamma1", "1.2.3+24"]
        #endif
        
        fixture(name: "DependencyResolution/External/Complex", tags: tags) { prefix in
            XCTAssertBuilds(prefix.appending("app"), configurations: [.Debug])
            XCTAssertDirectoryExists(prefix.appending("app/Packages/DeckOfPlayingCards-1.2.3-beta5"))
            XCTAssertDirectoryExists(prefix.appending("app/Packages/FisherYates-1.3.4-alpha.beta.gamma1"))
            XCTAssertDirectoryExists(prefix.appending("app/Packages/PlayingCard-1.2.3+24"))
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

    static var allTests = [
        ("testSingleModuleLibrary", testSingleModuleLibrary),
        ("testSingleModuleExecutable", testSingleModuleExecutable),
        ("testSingleModuleCustomizedName", testSingleModuleCustomizedName),
        ("testSingleModuleSubfolderWithSwiftSuffix", testSingleModuleSubfolderWithSwiftSuffix),
        ("testMultipleModulesLibraries", testMultipleModulesLibraries),
        ("testMultipleModulesExecutables", testMultipleModulesExecutables),
        ("testPackageIdentifiers", testPackageIdentifiers),
        ("testMadeValidWithExclude", testMadeValidWithExclude),
    ]
}


// MARK: Utility

extension ValidLayoutsTestCase {
    func runLayoutFixture(name: RelativePath, line: UInt = #line, body: @noescape(AbsolutePath) throws -> Void) {
        let name = RelativePath("ValidLayouts/\(name.asString)")

        // 1. Rooted layout
        fixture(name: name, file: #file, line: line, body: body)

        // 2. Move everything to a directory called "Sources"
        fixture(name: name, file: #file, line: line) { prefix in
            let files = try! localFileSystem.getDirectoryContents(prefix).filter{ $0.basename != "Package.swift" }
            let dir = prefix.appending("Sources")
            try Utility.makeDirectories(dir.asString)
            for file in files {
                try rename(old: prefix.appending(file).asString, new: dir.appending(file).asString)
            }
            try body(prefix)
        }

        // 3. Symlink some other directory to a directory called "Sources"
        fixture(name: name, file: #file, line: line) { prefix in
            let files = try! localFileSystem.getDirectoryContents(prefix).filter{ $0.basename != "Package.swift" }
            let dir = prefix.appending("Floobles")
            try Utility.makeDirectories(dir.asString)
            for file in files {
                try rename(old: prefix.appending(file).asString, new: dir.appending(file).asString)
            }
            try symlink(create: prefix.appending("Sources").asString, pointingAt: dir.asString, relativeTo: prefix.asString)
            try body(prefix)
        }
    }
}
