/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageDescription
import XCTest

class PackageTests: XCTestCase {
    func testMatchDependencyWithPreReleaseVersion() {
        // Tests matching dependency with pre-release suffixed version
        // Refs: https://bugs.swift.org/browse/SR-787

        let majorVersionSpecified: Package.Dependency = .Package(url: "", majorVersion: 1)
        XCTAssertFalse(majorVersionSpecified.versionRange ~= "2.0.0-alpha")
        XCTAssertFalse(majorVersionSpecified.versionRange ~= "2.0.0")

        let majorAndMinorVersionSpecified: Package.Dependency = .Package(url: "", majorVersion: 0, minor: 10)
        XCTAssertFalse(majorAndMinorVersionSpecified.versionRange ~= "0.11.0-test")
        XCTAssertFalse(majorAndMinorVersionSpecified.versionRange ~= "0.11.0")
    }

    static var allTests = [
        ("testMatchDependencyWithPreReleaseVersion", testMatchDependencyWithPreReleaseVersion),
    ]
}
