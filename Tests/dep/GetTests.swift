/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import sys
import XCTest
@testable import dep

class GetTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testRawCloneDoesNotCrashIfManifestIsNotPresent", testRawCloneDoesNotCrashIfManifestIsNotPresent),
        ]
    }

    func testRawCloneDoesNotCrashIfManifestIsNotPresent() {
        fixture(name: "102_mattts_dealer") {
            let path = Path.join($0, "FisherYates")
            try system("git", "-C", path, "rm", "Package.swift")
            try system("git", "-C", path, "commit", "-mwip")

            let rawClone = Sandbox.RawClone(path: path)
            XCTAssertEqual(rawClone.dependencies.count, 0)
        }
    }
}


