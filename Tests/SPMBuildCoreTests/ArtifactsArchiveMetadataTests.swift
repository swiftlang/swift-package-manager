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

import Basics
import PackageModel
import SPMBuildCore
import XCTest

final class ArtifactsArchiveMetadataTests: XCTestCase {
    func testParseMetadata() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.0",
                "artifacts": {
                    "protocol-buffer-compiler": {
                        "type": "executable",
                        "version": "3.5.1",
                        "variants": [
                            {
                                "path": "x86_64-apple-macosx/protoc",
                                "supportedTriples": ["x86_64-apple-macosx"]
                            },
                            {
                                "path": "x86_64-unknown-linux-gnu/protoc",
                                "supportedTriples": ["x86_64-unknown-linux-gnu"]
                            }
                        ]
                    }
                }
            }
            """
        )

        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata, try ArtifactsArchiveMetadata(
            schemaVersion: "1.0",
            artifacts: [
                "protocol-buffer-compiler": ArtifactsArchiveMetadata.Artifact(
                    type: .executable,
                    version: "3.5.1",
                    variants: [
                        ArtifactsArchiveMetadata.Variant(
                            path: "x86_64-apple-macosx/protoc",
                            supportedTriples: [Triple("x86_64-apple-macosx")]
                        ),
                        ArtifactsArchiveMetadata.Variant(
                            path: "x86_64-unknown-linux-gnu/protoc",
                            supportedTriples: [Triple("x86_64-unknown-linux-gnu")]
                        ),
                    ]
                ),
            ]
        ))
    }
    func testParseMetadataWithoutSupportedTriple() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.0",
                "artifacts": {
                    "protocol-buffer-compiler": {
                        "type": "executable",
                        "version": "3.5.1",
                        "variants": [
                            {
                                "path": "x86_64-apple-macosx/protoc"
                            },
                            {
                                "path": "x86_64-unknown-linux-gnu/protoc",
                                "supportedTriples": null
                            }
                        ]
                    }
                }
            }
            """
        )

        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata, ArtifactsArchiveMetadata(
            schemaVersion: "1.0",
            artifacts: [
                "protocol-buffer-compiler": ArtifactsArchiveMetadata.Artifact(
                    type: .executable,
                    version: "3.5.1",
                    variants: [
                        ArtifactsArchiveMetadata.Variant(
                            path: "x86_64-apple-macosx/protoc",
                            supportedTriples: nil
                        ),
                        ArtifactsArchiveMetadata.Variant(
                            path: "x86_64-unknown-linux-gnu/protoc",
                            supportedTriples: nil
                        ),
                    ]
                ),
            ]
        ))

        let binaryTarget = BinaryModule(
            name: "protoc", kind: .artifactsArchive, path: .root, origin: .local
        )
        // No supportedTriples with binaryTarget should be rejected
        XCTAssertThrowsError(
            try binaryTarget.parseExecutables(
                for: Triple("x86_64-apple-macosx"), fileSystem: fileSystem
            )
        )
    }
    func testParseMetadataLibrary() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.2",
                "artifacts": {
                    "KrabbyPatty": {
                        "type": "library",
                        "version": "1.0.0",
                        "variants": [{ "path": "KrabbyPatty" }]
                    }
                }
            }
            """
        )

        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata, ArtifactsArchiveMetadata(
            schemaVersion: "1.2",
            artifacts: [
                "KrabbyPatty": ArtifactsArchiveMetadata.Artifact(
                    type: .library,
                    version: "1.0.0",
                    variants: [
                        ArtifactsArchiveMetadata.Variant(
                            path: "KrabbyPatty",
                            supportedTriples: nil
                        ),
                    ]
                ),
            ]
        ))

        let binaryTarget = BinaryModule(
            name: "KrabbyPatty", kind: .artifactsArchive, path: .root, origin: .local
        )
        let libraries = try binaryTarget.parseLibraries(
            for: Triple("x86_64-apple-macosx"), fileSystem: fileSystem
        )
        XCTAssertEqual(libraries.count, 1)
    }

    func testParseMetadataLibraryDiagnoseUnexpectedTriple() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.2",
                "artifacts": {
                    "KrabbyPatty": {
                        "type": "library",
                        "version": "1.0.0",
                        "variants": [
                            {
                                "path": "KrabbyPatty",
                                "supportedTriples": ["x86_64-unknown-linux-gnu"]
                            }
                        ]
                    }
                }
            }
            """
        )

        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata, ArtifactsArchiveMetadata(
            schemaVersion: "1.2",
            artifacts: [
                "KrabbyPatty": ArtifactsArchiveMetadata.Artifact(
                    type: .library,
                    version: "1.0.0",
                    variants: [
                        ArtifactsArchiveMetadata.Variant(
                            path: "KrabbyPatty",
                            supportedTriples: [try Triple("x86_64-unknown-linux-gnu")]
                        ),
                    ]
                ),
            ]
        ))

        let binaryTarget = BinaryModule(
            name: "KrabbyPatty", kind: .artifactsArchive, path: .root, origin: .local
        )
        // library artifacts must not specify supported triples
        XCTAssertThrowsError(
            try binaryTarget.parseLibraries(
                for: Triple("x86_64-unknown-linux-gnu"), fileSystem: fileSystem
            )
        )
    }

    func testParseMetadataLibraryDiagnoseMultipleVariants() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.2",
                "artifacts": {
                    "KrabbyPatty": {
                        "type": "library",
                        "version": "1.0.0",
                        "variants": [
                            {
                                "path": "KrabbyPatty1",
                            },
                            {
                                "path": "KrabbyPatty2",
                            }
                        ]
                    }
                }
            }
            """
        )

        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata, ArtifactsArchiveMetadata(
            schemaVersion: "1.2",
            artifacts: [
                "KrabbyPatty": ArtifactsArchiveMetadata.Artifact(
                    type: .library,
                    version: "1.0.0",
                    variants: [
                        ArtifactsArchiveMetadata.Variant(
                            path: "KrabbyPatty1",
                            supportedTriples: nil
                        ),
                        ArtifactsArchiveMetadata.Variant(
                            path: "KrabbyPatty2",
                            supportedTriples: nil
                        ),
                    ]
                ),
            ]
        ))

        let binaryTarget = BinaryModule(
            name: "KrabbyPatty", kind: .artifactsArchive, path: .root, origin: .local
        )
        // library artifacts must not specify supported triples
        XCTAssertThrowsError(
            try binaryTarget.parseLibraries(
                for: Triple("x86_64-unknown-linux-gnu"), fileSystem: fileSystem
            )
        )
    }
}
