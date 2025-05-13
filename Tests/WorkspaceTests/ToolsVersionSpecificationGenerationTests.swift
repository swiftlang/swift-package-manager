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
import Foundation

///
/// This file tests the generation of a Swift tools version specification from a known version.
///

import Testing
import PackageModel

import struct TSCUtility.Version

/// Test cases for the generation of Swift tools version specifications.
fileprivate struct ToolsVersionSpecificationGenerationTests {
    /// Tests the generation of Swift tools version specifications.
    @Test
    func toolsVersionSpecificationGeneration() throws {
        let versionWithNonZeroPatch = ToolsVersion(version: Version(4, 3, 2))
        #expect(versionWithNonZeroPatch.specification() == "// swift-tools-version:4.3.2")
        #expect(versionWithNonZeroPatch.specification(roundedTo: .automatic) == "// swift-tools-version:4.3.2")
        #expect(versionWithNonZeroPatch.specification(roundedTo: .minor) == "// swift-tools-version:4.3")
        #expect(versionWithNonZeroPatch.specification(roundedTo: .patch) == "// swift-tools-version:4.3.2")

        let versionWithZeroPatch = ToolsVersion.v5_3 // 5.3.0
        #expect(versionWithZeroPatch.specification() == "// swift-tools-version:5.3")
        #expect(versionWithZeroPatch.specification(roundedTo: .automatic) == "// swift-tools-version:5.3")
        #expect(versionWithZeroPatch.specification(roundedTo: .minor) == "// swift-tools-version:5.3")
        #expect(versionWithZeroPatch.specification(roundedTo: .patch) == "// swift-tools-version:5.3.0")

        let newMajorVersion = ToolsVersion.v5 // 5.0.0
        #expect(newMajorVersion.specification() == "// swift-tools-version:5.0")
        #expect(newMajorVersion.specification(roundedTo: .automatic) == "// swift-tools-version:5.0")
        #expect(newMajorVersion.specification(roundedTo: .minor) == "// swift-tools-version:5.0")
        #expect(newMajorVersion.specification(roundedTo: .patch) == "// swift-tools-version:5.0.0")

        let allZeroVersion = ToolsVersion(version: Version(0, 0, 0))
        #expect(allZeroVersion.specification() == "// swift-tools-version:0.0")
        #expect(allZeroVersion.specification(roundedTo: .automatic) == "// swift-tools-version:0.0")
        #expect(allZeroVersion.specification(roundedTo: .minor) == "// swift-tools-version:0.0")
        #expect(allZeroVersion.specification(roundedTo: .patch) == "// swift-tools-version:0.0.0")
    }

}
