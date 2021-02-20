/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Build
import TSCBasic
import TSCUtility
import XCTest

final class ToolsArchiveMetadataTests: XCTestCase {
    func testParseMetadata() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.writeFileContents(
            AbsolutePath("/info.json"),
            bytes: ByteString(encodingAsUTF8: """
             {
                 "schemaVersion": "1.0",
                 "availableTools": {
                     "protocol-buffer-compiler": [
                         {
                             "path": "x86_64-apple-macosx/protoc",
                             "supportedTriplets": ["x86_64-apple-macosx"]
                         },
                         {
                             "path": "x86_64-unknown-linux-gnu/protoc",
                             "supportedTriplets": ["x86_64-unknown-linux-gnu"]
                         }
                     ]
                 }
             }
            """)
        )

        let metadata = try ToolsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: .root)
        XCTAssertEqual(metadata, try ToolsArchiveMetadata(
            schemaVersion: "1.0",
            tools: [
                "protocol-buffer-compiler": [
                    ToolsArchiveMetadata.Support(
                        path: "x86_64-apple-macosx/protoc",
                        supportedTriplets: [Triple("x86_64-apple-macosx")]
                    ),
                    ToolsArchiveMetadata.Support(
                        path: "x86_64-unknown-linux-gnu/protoc",
                        supportedTriplets: [Triple("x86_64-unknown-linux-gnu")]
                    ),
                ],
            ]
        ))
    }
}
