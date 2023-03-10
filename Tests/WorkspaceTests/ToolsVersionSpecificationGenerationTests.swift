//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

///
/// This file tests the generation of a Swift tools version specification from a known version.
///

import XCTest
import PackageModel

import struct TSCUtility.Version

/// Test cases for the generation of Swift tools version specifications.
class ToolsVersionSpecificationGenerationTests: XCTestCase {
    /// Tests the generation of Swift tools version specifications.
    func testToolsVersionSpecificationGeneration() throws {
        let versionWithNonZeroPatch = ToolsVersion(version: Version(4, 3, 2))
        XCTAssertEqual(versionWithNonZeroPatch.specification(), "// swift-tools-version:4.3.2")
        XCTAssertEqual(versionWithNonZeroPatch.specification(roundedTo: .automatic), "// swift-tools-version:4.3.2")
        XCTAssertEqual(versionWithNonZeroPatch.specification(roundedTo: .minor), "// swift-tools-version:4.3")
        XCTAssertEqual(versionWithNonZeroPatch.specification(roundedTo: .patch), "// swift-tools-version:4.3.2")
        
        let versionWithZeroPatch = ToolsVersion.v5_3 // 5.3.0
        XCTAssertEqual(versionWithZeroPatch.specification(), "// swift-tools-version:5.3")
        XCTAssertEqual(versionWithZeroPatch.specification(roundedTo: .automatic), "// swift-tools-version:5.3")
        XCTAssertEqual(versionWithZeroPatch.specification(roundedTo: .minor), "// swift-tools-version:5.3")
        XCTAssertEqual(versionWithZeroPatch.specification(roundedTo: .patch), "// swift-tools-version:5.3.0")
        
        let newMajorVersion = ToolsVersion.v5 // 5.0.0
        XCTAssertEqual(newMajorVersion.specification(), "// swift-tools-version:5.0")
        XCTAssertEqual(newMajorVersion.specification(roundedTo: .automatic), "// swift-tools-version:5.0")
        XCTAssertEqual(newMajorVersion.specification(roundedTo: .minor), "// swift-tools-version:5.0")
        XCTAssertEqual(newMajorVersion.specification(roundedTo: .patch), "// swift-tools-version:5.0.0")
    }
}
