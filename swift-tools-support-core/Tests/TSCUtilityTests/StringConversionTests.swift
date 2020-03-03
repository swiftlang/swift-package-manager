/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCUtility

class StringConversionTests: XCTestCase {

    func testManglingToBundleIdentifier() {
        XCTAssertEqual("foo".spm_mangledToBundleIdentifier(), "foo")
        XCTAssertEqual("1foo__ò".spm_mangledToBundleIdentifier(), "1foo---")
        XCTAssertEqual("com.example.🐴🔄".spm_mangledToBundleIdentifier(), "com.example.----")
        XCTAssertEqual("٠٠٠".spm_mangledToBundleIdentifier(), "---")
    }

    func testManglingToC99ExtendedIdentifier() {

        // Simple cases.
        XCTAssertEqual("foo".spm_mangledToC99ExtendedIdentifier(), "foo")

        // Edge cases.
        XCTAssertEqual("".spm_mangledToC99ExtendedIdentifier(), "")
        XCTAssertEqual("_".spm_mangledToC99ExtendedIdentifier(), "_")
        XCTAssertEqual("\n".spm_mangledToC99ExtendedIdentifier(), "_")

        // Invalid non-leading characters.
        XCTAssertEqual("_-".spm_mangledToC99ExtendedIdentifier(), "__")
        XCTAssertEqual("foo-bar".spm_mangledToC99ExtendedIdentifier(), "foo_bar")

        // Invalid leading characters.
        XCTAssertEqual("1".spm_mangledToC99ExtendedIdentifier(), "_")
        XCTAssertEqual("1foo".spm_mangledToC99ExtendedIdentifier(), "_foo")
        XCTAssertEqual("٠٠٠".spm_mangledToC99ExtendedIdentifier(), "_٠٠")
        XCTAssertEqual("12 3".spm_mangledToC99ExtendedIdentifier(), "_2_3")

        // FIXME: There are lots more interesting test cases to add here.
        var str1 = ""
        str1.spm_mangleToC99ExtendedIdentifier()
        XCTAssertEqual(str1, "")

        var str2 = "_"
        str2.spm_mangleToC99ExtendedIdentifier()
        XCTAssertEqual(str2, "_")

        var str3 = "-"
        str3.spm_mangleToC99ExtendedIdentifier()
        XCTAssertEqual(str3, "_")
    }
}
