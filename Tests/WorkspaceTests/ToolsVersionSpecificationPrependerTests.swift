// WorkspaceTests/ToolsVersionSpecificationPrependerTests.swift
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
/// This file tests global functions `prependToolsVersionSpecification(toDefaultManifestIn:specifying:fileSystem:)` and `prependToolsVersionSpecification(toManifestAt:specifying:fileSystem:)`.
///
// -----------------------------------------------------------------------------

import XCTest

import TSCBasic
import PackageModel
import Workspace

/// Test cases for `prependToolsVersionSpecification(toDefaultManifestIn:specifying:fileSystem:)` and `prependToolsVersionSpecification(toManifestAt:specifying:fileSystem:)`.
class ToolsVersionSpecificationPrependerTests: XCTestCase {
    
    /// Tests `prependToolsVersionSpecification(toDefaultManifestIn:specifying:fileSystem:)`.
    func testNonVersionSpecificManifests() throws {
        // Empty file.
        var stream = BufferedOutputByteStream()
        stream <<< ""

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n")
        }

        // File with just a new line.
        stream = BufferedOutputByteStream()
        stream <<< "\n"

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n\n")
        }

        // File with some contents.
        stream = BufferedOutputByteStream()
        stream <<< "let package = ... \n"

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\nlet package = ... \n")
        }

        // File already having a valid version specifier.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:3.1.2\n"
        stream <<< "..."

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }

        // Write a version with zero in patch number.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:3.1.2\n"
        stream <<< "..."

        prependToolsVersionSpecificationToDefaultManifest(stream: stream, version: ToolsVersion(version: "2.1.0")) { result in
            XCTAssertEqual(result, "// swift-tools-version:2.1\n...")
        }

        // Contents with invalid tools version specification (ignoring the validity of the version specifier).
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tool-version:3.1.2\n"
        stream <<< "..."

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n// swift-tool-version:3.1.2\n...")
        }

        // Contents with invalid version specifier.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:-3.1.2\n"
        stream <<< "..."

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }

        // Contents with invalid version specifier and some meta data.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:-3.1.2;hello\n"
        stream <<< "..."

        prependToolsVersionSpecificationToDefaultManifest(stream: stream) { result in
            // Note: Right now we lose the metadata but if we ever start using it, we should preserve it.
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }

        // Try to write a version with prerelease and build meta data.
        let toolsVersion = ToolsVersion(version: "4.1.2-alpha.beta+sha.1234")
        
        stream = BufferedOutputByteStream()
        stream <<< "let package = ... \n"
        
        prependToolsVersionSpecificationToDefaultManifest(
            stream: stream,
            version: toolsVersion
        ) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\nlet package = ... \n")
        }
    }
    
    // Private functions are not run in tests.
    private func testVersionSpecificManifests() throws {
        // TODO: Add the functionality and tests for version-specific manifests too.
    }

    func testZeroedPatchVersion() {
        XCTAssertEqual(ToolsVersion(version: "4.2.1").zeroedPatch.description, "4.2.0")
        XCTAssertEqual(ToolsVersion(version: "4.2.0").zeroedPatch.description, "4.2.0")
        XCTAssertEqual(ToolsVersion(version: "6.0.129").zeroedPatch.description, "6.0.0")
    }
    
    /// Does the boilerplate filesystem preparations, then calls `prependToolsVersionSpecification(toDefaultManifestIn:specifying:fileSystem:)`, for `testNonVersionSpecificManifests()`.
    /// - Parameters:
    ///   - stream: The stream to read from and write to the filesystem.
    ///   - version: The Swift tools version to specify.
    ///   - resultHandler: The result handler.
    func prependToolsVersionSpecificationToDefaultManifest(
        stream: BufferedOutputByteStream,
        version: ToolsVersion = ToolsVersion(version: "4.1.2"),
        resultHandler: (ByteString) -> Void
    ) {
        do {
            let inMemoryFileSystem: FileSystem = InMemoryFileSystem()

            let manifestFilePath = AbsolutePath("/pkg/Package.swift")

            try inMemoryFileSystem.createDirectory(manifestFilePath.parentDirectory, recursive: true)
            try inMemoryFileSystem.writeFileContents(manifestFilePath, bytes: stream.bytes)

            try prependToolsVersionSpecification(
                toDefaultManifestIn: manifestFilePath.parentDirectory, specifying: version, fileSystem: inMemoryFileSystem)

            resultHandler(try inMemoryFileSystem.readFileContents(manifestFilePath))
        } catch {
            XCTFail("Failed with error \(error)")
        }
    }
    
}
