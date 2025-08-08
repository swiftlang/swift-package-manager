//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

///
/// This file tests `Workspace.rewriteToolsVersionSpecification(toDefaultManifestIn:specifying:fileSystem:)`.
///

import Basics
import PackageModel
@testable import Workspace
import Testing

/// Test cases for `rewriteToolsVersionSpecification(toDefaultManifestIn:specifying:fileSystem:)`
fileprivate struct ToolsVersionSpecificationRewriterTests {

    struct NonVersionSpecificManifestTestData: Identifiable {
        let id: String
        let content: String
        let version: ToolsVersion
        let expected: String
    }
    @Test(
        arguments: [
            NonVersionSpecificManifestTestData(
                id: "Empty file.",
                content: "",
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\n"
            ),
            NonVersionSpecificManifestTestData(
                id: "File with just a new line.",
                content: "\n",
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\n\n"
            ),
            NonVersionSpecificManifestTestData(
                id: "File with some contents.",
                content: "let package = ... \n",
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\nlet package = ... \n"
            ),
            NonVersionSpecificManifestTestData(
                id: "File already having a valid version specifier.",
                content: """
                    // swift-tools-version:3.1.2
                    ...
                    """,
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\n..."
            ),
            NonVersionSpecificManifestTestData(
                id: "File already having a valid version specifier.",
                content: """
                    // swift-tools-version:3.1.2
                    ...
                    """,
                version: ToolsVersion(version: "2.1.0"),
                expected: "// swift-tools-version:2.1\n..."
            ),
            NonVersionSpecificManifestTestData(
                id: "Contents with invalid tools version specification (ignoring the validity of the version specifier).",
                content: """
                    // swift-tool-version:3.1.2
                    ...
                    """,
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\n// swift-tool-version:3.1.2\n..."
            ),
            NonVersionSpecificManifestTestData(
                id: "Contents with invalid version specifier.",
                content: """
                    // swift-tools-version:3.1.2
                    ...
                    """,
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\n..."
            ),
            NonVersionSpecificManifestTestData(
                id: "Contents with invalid version specifier and some meta data.",
                content: """
                    // swift-tools-version:3.1.2
                    ...
                    """,
                version: ToolsVersion(version: "4.1.2"),
                expected: "// swift-tools-version:4.1.2\n..."
            ),
            NonVersionSpecificManifestTestData(
                id: "Try to write a version with prerelease and build meta data.",
                content: "let package = ... \n",
                version: ToolsVersion(version: "4.1.2-alpha.beta+sha.1234"),
                expected: "// swift-tools-version:4.1.2\nlet package = ... \n"
            ),
        ]
    )
    func nonVersionSpecificManifests(_ data: NonVersionSpecificManifestTestData) throws {
        let content = data.content
        let version = data.version
        let expected = data.expected

        let inMemoryFileSystem = InMemoryFileSystem()

        let manifestFilePath = AbsolutePath("/pkg/Package.swift")

        try inMemoryFileSystem.createDirectory(manifestFilePath.parentDirectory, recursive: true)
        try inMemoryFileSystem.writeFileContents(manifestFilePath, string: content)

        try ToolsVersionSpecificationWriter.rewriteSpecification(
            manifestDirectory: manifestFilePath.parentDirectory,
            toolsVersion: version,
            fileSystem: inMemoryFileSystem
        )

        // resultHandler(try inMemoryFileSystem.readFileContents(manifestFilePath))
        let actual = try inMemoryFileSystem.readFileContents(manifestFilePath)
        #expect(actual.validDescription == expected, "Actual is not expected")
    }

    @Test
    func manifestAccessFailures() throws {
        let toolsVersion = ToolsVersion.v5_3

        let inMemoryFileSystem = InMemoryFileSystem()
        let manifestFilePath = AbsolutePath("/pkg/Package.swift/Package.swift")
        try inMemoryFileSystem.createDirectory(manifestFilePath.parentDirectory, recursive: true)  // /pkg/Package.swift/

        // Test `ManifestAccessError.Kind.isADirectory`

        #expect {
            try ToolsVersionSpecificationWriter.rewriteSpecification(
                manifestDirectory: manifestFilePath.parentDirectory.parentDirectory,  // /pkg/
                toolsVersion: toolsVersion,
                fileSystem: inMemoryFileSystem
            )
        } throws: { error in
            let error = try #require(
                error as? ToolsVersionSpecificationWriter.ManifestAccessError,
                "a ManifestAccessError should've been thrown"
            )
            let isExpectedKind = (error.kind == .isADirectory)
            let isExpectedDescription = (error.description == "no accessible Swift Package Manager manifest file found at '\(manifestFilePath.parentDirectory)'; the path is a directory; a file is expected")

            return isExpectedKind && isExpectedDescription
        }

        // Test `ManifestAccessError.Kind.noSuchFileOrDirectory`
        #expect {
            try ToolsVersionSpecificationWriter.rewriteSpecification(
                manifestDirectory: manifestFilePath.parentDirectory,  // /pkg/Package.swift/
                toolsVersion: toolsVersion,
                fileSystem: inMemoryFileSystem
            )
        } throws: { error in
            let error = try #require(
                error as? ToolsVersionSpecificationWriter.ManifestAccessError,
                "a ManifestAccessError should've been thrown"
            )
            let isExpectedKind = (error.kind == .noSuchFileOrDirectory)
            let isExpectedDescription = (error.description == "no accessible Swift Package Manager manifest file found at '\(manifestFilePath)'; a component of the path does not exist, or the path is an empty string")

            return isExpectedKind && isExpectedDescription
        }
    }

    // Private functions are not run in tests.
    @Test
    func versionSpecificManifests() throws {

    }

    @Test
    func zeroedPatchVersion() {
        #expect(ToolsVersion(version: "4.2.1").zeroedPatch.description == "4.2.0")
        #expect(ToolsVersion(version: "4.2.0").zeroedPatch.description == "4.2.0")
        #expect(ToolsVersion(version: "6.0.129").zeroedPatch.description == "6.0.0")
    }

}
