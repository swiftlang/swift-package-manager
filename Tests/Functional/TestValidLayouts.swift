/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Path
import func POSIX.symlink
import func Utility.walk
import func POSIX.rename
import func POSIX.mkdir
import func POSIX.popen
import XCTest

class ValidLayoutsTestCase: XCTestCase {

    func testSingleModuleLibrary() {
        runLayoutFixture(name: "SingleModule/Library") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "Library.swiftmodule")
        }
    }

    func testSingleModuleExecutable() {
        runLayoutFixture(name: "SingleModule/Executable") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "Executable")
        }
    }

    func testSingleModuleCustomizedName() {

        // Package.swift for a single module with a customized name
        // names that target after the package name

        runLayoutFixture(name: "SingleModule/CustomizedName") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "Bar.swiftmodule")
        }
    }

    func testSingleModuleSubfolderWithSwiftSuffix() {
        fixture(name: "ValidLayouts/SingleModule/SubfolderWithSwiftSuffix", file: #file, line: #line) { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "Bar.swiftmodule")
        }
    }

    func testMultipleModulesLibraries() {
        runLayoutFixture(name: "MultipleModules/Libraries") { prefix in
            XCTAssertBuilds(prefix)
            for x in ["Bar", "Baz", "Foo"] {
                XCTAssertFileExists(prefix, ".build", "debug", "\(x).swiftmodule")
            }
        }
    }

    func testMultipleModulesExecutables() {
        runLayoutFixture(name: "MultipleModules/Executables") { prefix in
            XCTAssertBuilds(prefix)
            for x in ["Bar", "Baz", "Foo"] {
                let output = try popen(["\(prefix)/.build/debug/\(x)"])
                XCTAssertEqual(output, "\(x)\n")
            }
        }
    }

    func testPackageIdentifiers() {
        #if os(OSX)
            // this because sort orders vary on Linux on Mac currently
            let tags = ["1.3.4-alpha.beta.gamma1", "1.2.3+24", "1.2.3", "1.2.3-beta5"]
        #else
            let tags = ["1.2.3", "1.2.3-beta5", "1.3.4-alpha.beta.gamma1", "1.2.3+24"]
        #endif
        
        fixture(name: "DependencyResolution/External/Complex", tags: tags) { prefix in
            XCTAssertBuilds(prefix, "app", configurations: [.Debug])
            XCTAssertDirectoryExists(prefix, "app/Packages/DeckOfPlayingCards-1.2.3-beta5")
            XCTAssertDirectoryExists(prefix, "app/Packages/FisherYates-1.3.4-alpha.beta.gamma1")
            XCTAssertDirectoryExists(prefix, "app/Packages/PlayingCard-1.2.3+24")
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
}


//MARK: Utility

extension ValidLayoutsTestCase {
    func runLayoutFixture(name name: String, line: UInt = #line, @noescape body: (String) throws -> Void) {
        let name = "ValidLayouts/\(name)"

        // 1. Rooted layout
        fixture(name: name, file: #file, line: line, body: body)

        // 2. Move everything to a directory called "Sources"
        fixture(name: name, file: #file, line: line) { prefix in
            let files = walk(prefix, recursively: false).filter{ $0.basename != "Package.swift" }
            let dir = try mkdir(prefix, "Sources")
            for file in files {
                let tip = Path(file).relative(to: prefix)
                try rename(old: file, new: Path.join(dir, tip))
            }
            try body(prefix)
        }

        // 3. Symlink some other directory to a directory called "Sources"
        fixture(name: name, file: #file, line: line) { prefix in
            let files = walk(prefix, recursively: false).filter{ $0.basename != "Package.swift" }
            let dir = try mkdir(prefix, "Floobles")
            for file in files {
                let tip = Path(file).relative(to: prefix)
                try rename(old: file, new: Path.join(dir, tip))
            }
            try symlink(create: "\(prefix)/Sources", pointingAt: dir, relativeTo: prefix)
            try body(prefix)
        }
    }
}


#if os(Linux)
extension DependencyResolutionTestCase: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testInternalSimple", testInternalSimple),
            ("testInternalComplex", testInternalComplex),
            ("testExternalSimple", testExternalSimple),
            ("testExternalComplex", testExternalComplex),
        ]
    }
}

extension InvalidLayoutsTestCase: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testNoTargets", testNoTargets),
            ("testMultipleRoots", testMultipleRoots),
            ("testInvalidLayout1", testInvalidLayout1),
            ("testInvalidLayout2", testInvalidLayout2),
            ("testInvalidLayout3", testInvalidLayout3),
            ("testInvalidLayout4", testInvalidLayout4),
            ("testInvalidLayout5", testInvalidLayout5),
        ]
    }
}

extension MiscellaneousTestCase: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testPrintsSelectedDependencyVersion", testPrintsSelectedDependencyVersion),
            ("testManifestExcludes1", testManifestExcludes1),
            ("testManifestExcludes2", testManifestExcludes2),
            ("testManifestExcludes3", testManifestExcludes3),
            ("testTestDependenciesSimple", testTestDependenciesSimple),
            ("testTestDependenciesComplex", testTestDependenciesComplex),
            ("testPassExactDependenciesToBuildCommand", testPassExactDependenciesToBuildCommand),
            ("testCanBuildMoreThanTwiceWithExternalDependencies", testCanBuildMoreThanTwiceWithExternalDependencies),
            ("testNoArgumentsExitsWithOne", testNoArgumentsExitsWithOne),
            ("testCompileFailureExitsGracefully", testCompileFailureExitsGracefully),
            ("testDependenciesWithVPrefixTagsWork", testDependenciesWithVPrefixTagsWork),
            ("testCanBuildIfADependencyAlreadyCheckedOut", testCanBuildIfADependencyAlreadyCheckedOut),
            ("testCanBuildIfADependencyClonedButThenAborted", testCanBuildIfADependencyClonedButThenAborted),
            ("testTipHasNoPackageSwift", testTipHasNoPackageSwift),
            ("testFailsIfVersionTagHasNoPackageSwift", testFailsIfVersionTagHasNoPackageSwift),
            ("testPackageManagerDefine", testPackageManagerDefine),
            ("testInternalDependencyEdges", testInternalDependencyEdges),
            ("testExternalDependencyEdges1", testExternalDependencyEdges1),
            ("testExternalDependencyEdges2", testExternalDependencyEdges2),
        ]
    }
}


extension ValidLayoutsTestCase: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
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
}
#endif
