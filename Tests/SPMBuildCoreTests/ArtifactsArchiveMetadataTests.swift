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
import struct TSCBasic.StringError

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

    // Mirrors the worked examples in Sources/PackageManagerDocs/Documentation.docc/ArtifactBundleReference.md.
    // If this test starts failing, that doc's JSON examples need to be updated too.
    @Test
    func parseDocumentedExecutableExample() throws {
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

        _ = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
    }

    @Test
    func parseDocumentedStaticLibraryExample() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            "/info.json",
            string: """
            {
                "schemaVersion": "1.0",
                "artifacts": {
                    "simple": {
                        "type": "staticLibrary",
                        "version": "1.0.0",
                        "variants": [
                            {
                                "path": "dist/macOS/libSimple.a",
                                "supportedTriples": ["arm64-apple-macosx", "x86_64-apple-macosx"],
                                "staticLibraryMetadata": {
                                    "headerPaths": ["include"],
                                    "moduleMapPath": "include/simple.modulemap"
                                }
                            },
                            {
                                "path": "dist/linux/libSimple_x86_64.a",
                                "supportedTriples": ["x86_64-unknown-linux-gnu"],
                                "staticLibraryMetadata": {
                                    "headerPaths": ["include"],
                                    "moduleMapPath": "include/simple.modulemap"
                                }
                            },
                            {
                                "path": "dist/windows/Simple_x86_64.lib",
                                "supportedTriples": ["x86_64-unknown-windows-msvc"],
                                "staticLibraryMetadata": {
                                    "headerPaths": ["include"],
                                    "moduleMapPath": "include/simple.modulemap"
                                }
                            }
                        ]
                    }
                }
            }
            """
        )

        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        let artifact = try #require(metadata.artifacts["simple"])
        #expect(artifact.type == .staticLibrary)
        #expect(artifact.variants.count == 3)
        #expect(artifact.variants.allSatisfy { $0.staticLibraryMetadata?.moduleMapPath != nil })
    }

    @Test(
        arguments: [
            (
                infoPathName: AbsolutePath("/info.json"),
                contents: """
                {
                    "schemaVersion": 1.0, 
                    "artifacts": {}
                }
                """,
                expectedError: StringError("Type mismatch in ArtifactsArchive info.json at '/info.json'. Key 'schemaVersion' expected type 'String'."),
                id: "Type Mismatch",
            ),
            (
                infoPathName: AbsolutePath("/info.json"),
                contents: """
                {
                    "schemaVersion": "1.0",
                    "artifacts": {
                        "my-artifact": {
                            "type": "executable",
                            "variants": []
                    }
                }
                """,
                expectedError: StringError("Invalid JSON in ArtifactsArchive info.json at '/info.json': The given data was not valid JSON."),
                id: "Invalid JSON",
            
            ),
            (
                infoPathName: AbsolutePath("/info.json"),
                contents: """
                {
                    "schemaVersion": "1.0",
                    "artifacts": {
                        "my-artifact": {
                            "type": "executable",
                            "variants": []
                        }
                    }
                }
                """,
                expectedError: StringError("Missing required key 'version' in ArtifactsArchive info.json at '/info.json' in 'artifacts.my-artifact'."),
                id: "Missing Key",
            ),
            (
                infoPathName: AbsolutePath("/info.json"),
                contents: """
                {
                    "schemaVersion": "1.0",
                    "artifacts": {
                        "my-artifact": {
                            "type": "executable",
                            "version": null,
                            "variants": []
                        }
                    }
                }
                """,
                expectedError: StringError("Expected non-null value of type 'String' in ArtifactsArchive info.json at '/info.json'. Key 'artifacts.my-artifact.version' is null."),
                id: "Value not found",
            ),
        ],
    )
    func parseMetadataErrors(
        data: (infoPathName: AbsolutePath, contents: String, expectedError: StringError, id: String),
    ) throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            data.infoPathName,
            string: data.contents,
        )

        #expect(throws: data.expectedError) {
            _ = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        }
    }
}
