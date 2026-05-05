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

import Basics
import PackageModel
import Testing

struct ArtifactsArchiveMetadataTests {
    @Test
    func parseMetadata() throws {
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
        let expected = try ArtifactsArchiveMetadata(
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
                )
            ]
        )
        #expect(metadata == expected, "Actual is not as expected")
    }

    @Test
    func parseMetadataWithoutSupportedTriple() throws {
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
        let expected = ArtifactsArchiveMetadata(
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
                )
            ]
        )
        #expect(metadata == expected, "Actual is not as expected")

        let binaryTarget = BinaryModule(
            name: "protoc",
            kind: .artifactsArchive(types: [.executable]),
            path: .root,
            origin: .local
        )
        // No supportedTriples with binaryTarget should be rejected
        #expect(throws: (any Error).self) {
            try binaryTarget.parseExecutableArtifactArchives(
                for: Triple("x86_64-apple-macosx"),
                fileSystem: fileSystem
            )
        }
    }
}
