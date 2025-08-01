//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import PackageModel
import Testing

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct ToolsVersionTests {

    @Test(
        arguments: [
            (version: "3.1.0", expected: "3.1.0",),
            (version: "4.0", expected: "4.0.0",),
            (version: "0000104.0000000.4444", expected: "104.0.4444",),
            (version: "1.2.3-alpha.beta+1011", expected: "1.2.3",),
            (version: "1.2-alpha.beta+1011", expected: "1.2.0",),
            (version: "1.0.0-alpha+001", expected: "1.0.0",),
            (version: "1.0.0+20130313144700", expected: "1.0.0",),
            (version: "1.0.0-beta+exp.sha.5114f85", expected: "1.0.0",),
            (version: "1.0.0-alpha", expected: "1.0.0",),
            (version: "1.0.0-alpha.1", expected: "1.0.0",),
            (version: "1.0.0-0.3.7", expected: "1.0.0",),
            (version: "1.0.0-x.7.z.92", expected: "1.0.0",),
            (version: "1.0.0-alpha.beta", expected: "1.0.0",),
            (version: "1.0.0-beta", expected: "1.0.0",),
            (version: "1.0.0-beta.2", expected: "1.0.0",),
            (version: "1.0.0-beta.11", expected: "1.0.0",),
            (version: "1.0.0-rc.1", expected: "1.0.0",),
            (version: "1.0.0", expected: "1.0.0",),
            (version: "1.2.3-4", expected: "1.2.3",),
            (version: "2.7.2+asdf", expected: "2.7.2",),
            (version: "1.2.3-a.b.c.10.d.5", expected: "1.2.3",),
            (version: "2.7.2-foo+bar", expected: "2.7.2",),
            (version: "1.2.3-alpha.10.beta.0", expected: "1.2.3",),
            (version: "1.2.3-al.10.beta.0+bu.uni.ra", expected: "1.2.3",),
            (version: "1.2-al.10.beta.0+bu.uni.ra", expected: "1.2.0",),
        ],
    )
    func basicsValidVersions(
        version: String,
        expected: String
    ) async  throws {
        let toolsVersion = try #require(
            ToolsVersion(string: version),
            "Couldn't form a version with string: \(version)"
        )
        #expect(toolsVersion.description == expected)
    }

    @Test(
        arguments: [
            "1.2.3.4",
            "1.2-al..beta.0+bu.uni.ra",
            "1.2.33-al..beta.0+bu.uni.ra",
            ".1.0.0-x.7.z.92",
            "1.0.0-alpha.beta+",
            "1.0.0beta",
            "1.0.0-",
            "1.-2.3",
            "1.2.3d",
        ],
    )
    func basicInvalidVersionreturnsNil(
        version: String,
    ) async throws {
        #expect(ToolsVersion(string: version) == nil, "Valid version generate from version: \(version)")
    }

    @Test(
        arguments: [
            (version: "4.0.0", expectedRuntimeSubpath: "4"),
            (version: "4.1.0", expectedRuntimeSubpath: "4"),
            (version: "4.1.9", expectedRuntimeSubpath: "4"),
            (version: "4.2.0", expectedRuntimeSubpath: "4_2"),
            (version: "4.3.0", expectedRuntimeSubpath: "4_2"),
            (version: "5.0.0", expectedRuntimeSubpath: "4_2"),
            (version: "5.1.9", expectedRuntimeSubpath: "4_2"),
            (version: "6.0.0", expectedRuntimeSubpath: "4_2"),
            (version: "7.0.0", expectedRuntimeSubpath: "4_2"),
        ],
    )
    func runtimeSubpath(
        version: String,
        expectedRuntimeSubpath: String,
    ) async  throws {
        let version = try #require(ToolsVersion(string: version))

        #expect(version.runtimeSubpath.pathString == expectedRuntimeSubpath)
    }

    @Test(
        arguments: [
            (version: "4.0.0", expectedSwiftLanguageVersion: "4"),
            (version: "4.1.0", expectedSwiftLanguageVersion: "4"),
            (version: "4.1.9", expectedSwiftLanguageVersion: "4"),
            (version: "4.2.0", expectedSwiftLanguageVersion: "4.2"),
            (version: "4.3.0", expectedSwiftLanguageVersion: "4.2"),
            (version: "5.0.0", expectedSwiftLanguageVersion: "5"),
            (version: "5.1.9", expectedSwiftLanguageVersion: "5"),
            (version: "6.0.0", expectedSwiftLanguageVersion: "6"),
            (version: "7.0.0", expectedSwiftLanguageVersion: "6"),
        ],
    )
    func swiftLangVersion(
        version: String,
        expectedSwiftLanguageVersion: String,
    ) async  throws {
        let version = try #require(ToolsVersion(string: version))
        #expect(version.swiftLanguageVersion.description == expectedSwiftLanguageVersion)
    }
}
