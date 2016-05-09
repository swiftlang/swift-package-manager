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
            XCTAssertDirectoryExists(prefix, "Library.xcodeproj")
        }
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
