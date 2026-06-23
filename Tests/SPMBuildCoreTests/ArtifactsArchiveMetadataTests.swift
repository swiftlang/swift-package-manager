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
import SPMBuildCore
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
                ),
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
                ),
            ]
        )
        #expect(metadata == expected, "Actual is not as expected")

        let binaryTarget = BinaryModule(
            name: "protoc", kind: .artifactsArchive(types: [.executable]), path: .root, origin: .local
        )
        // No supportedTriples with binaryTarget should be rejected
        #expect(throws: (any Error).self) {
            try binaryTarget.parseExecutableArtifactArchives(
                for: Triple("x86_64-apple-macosx"), fileSystem: fileSystem
            )
        }
    }

    @Test
    func parseMacroArtifactArchivesSelectsHostVariant() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.0",
                "artifacts": {
                    "MyMacros": {
                        "type": "macro",
                        "version": "1.0.0",
                        "variants": [
                            {
                                "path": "arm64-apple-macosx/MyMacros",
                                "supportedTriples": ["arm64-apple-macosx"]
                            },
                            {
                                "path": "aarch64-unknown-linux-gnu/MyMacros",
                                "supportedTriples": ["aarch64-unknown-linux-gnu"]
                            }
                        ]
                    }
                }
            }
            """
        )

        let hostTriple = try Triple("arm64-apple-macosx")
        let binaryTarget = BinaryModule(
            name: "MyMacros", kind: .artifactsArchive(types: [.macro]), path: .root, origin: .local
        )
        let macros = try binaryTarget.parseMacroArtifactArchives(for: hostTriple, fileSystem: fileSystem)

        // One entry per variant; only the variant matching the host triple keeps a non-empty
        // `supportedTriples`, which is how the build plan picks the plugin to load.
        let hostMacros = macros.filter { !$0.supportedTriples.isEmpty }
        #expect(hostMacros.count == 1)
        #expect(hostMacros.first?.name == "MyMacros")
        #expect(hostMacros.first?.executablePath.pathString == "/arm64-apple-macosx/MyMacros")
        #expect(hostMacros.first?.supportedTriples == [hostTriple])
    }
}
