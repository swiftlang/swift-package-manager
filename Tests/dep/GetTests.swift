/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import XCTestCaseProvider
@testable import dep

import POSIX
import struct sys.Path

class GetTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> Void)] {
        return [
            ("testRawCloneDoesNotCrashIfManifestIsNotPresent", testRawCloneDoesNotCrashIfManifestIsNotPresent),
        ]
    }

    func testRawCloneDoesNotCrashIfManifestIsNotPresent() {
        fixture(name: "DependencyResolution/External/Complex") {
            let path = Path.join($0, "FisherYates")
            try system("git", "-C", path, "rm", "Package.swift")
            try system("git", "-C", path, "commit", "-mwip")

            let rawClone = Sandbox.RawClone(path: path)
            XCTAssertEqual(rawClone.dependencies.count, 0)
        }
    }
}


