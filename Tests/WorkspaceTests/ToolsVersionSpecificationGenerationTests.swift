// WorkspaceTests/ToolsVersionSpecificationGenerationTests.swift
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// This file tests the generation of a Swift tools version specification from a known version.
///
// -----------------------------------------------------------------------------

import XCTest
import PackageModel

/// Test cases for the generation of Swift tools version specifications.
class ToolsVersionSpecificationGenerationTests: XCTestCase {
    /// Tests the generation of Swift tools version specifications.
    func testToolsVersionSpecificationGeneration() throws {
        let versionWithNonZeroPatch = ToolsVersion(version: Version(4, 3, 2))
        XCTAssertEqual(versionWithNonZeroPatch.specification(), "// swift-tools-version:4.3.2")
        XCTAssertEqual(versionWithNonZeroPatch.specification(resolution: .automatic), "// swift-tools-version:4.3.2")
        XCTAssertEqual(versionWithNonZeroPatch.specification(resolution: .minor), "// swift-tools-version:4.3")
        XCTAssertEqual(versionWithNonZeroPatch.specification(resolution: .patch), "// swift-tools-version:4.3.2")
        
        let versionWithZeroPatch = ToolsVersion.v5_3 // 5.3.0
        XCTAssertEqual(versionWithZeroPatch.specification(), "// swift-tools-version:5.3")
        XCTAssertEqual(versionWithZeroPatch.specification(resolution: .automatic), "// swift-tools-version:5.3")
        XCTAssertEqual(versionWithZeroPatch.specification(resolution: .minor), "// swift-tools-version:5.3")
        XCTAssertEqual(versionWithZeroPatch.specification(resolution: .patch), "// swift-tools-version:5.3.0")
        
        let newMajorVersion = ToolsVersion.v5 // 5.0.0
        XCTAssertEqual(newMajorVersion.specification(), "// swift-tools-version:5.0")
        XCTAssertEqual(newMajorVersion.specification(resolution: .automatic), "// swift-tools-version:5.0")
        XCTAssertEqual(newMajorVersion.specification(resolution: .minor), "// swift-tools-version:5.0")
        XCTAssertEqual(newMajorVersion.specification(resolution: .patch), "// swift-tools-version:5.0.0")
    }
}
