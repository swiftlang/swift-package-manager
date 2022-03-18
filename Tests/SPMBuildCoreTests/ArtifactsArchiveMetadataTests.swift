//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SPMBuildCore
import TSCBasic
import XCTest

import struct TSCUtility.Triple

final class ArtifactsArchiveMetadataTests: XCTestCase {
    func testParseMetadata() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            AbsolutePath("/info.json"),
            bytes: ByteString(encodingAsUTF8: """
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
            """)
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
}
