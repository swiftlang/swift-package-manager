//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@testable import PackageModel
import Testing

@Suite
struct SwiftSDKAliasIndexTests {
    private let decoder = JSONDecoder.makeWithDefaults()
    private let encoder = JSONEncoder.makeWithDefaults(prettified: true)

    @Test
    func parseValidAliasIndex() throws {
        let json = """
        {
            "schemaVersion": "1.0",
            "remote": "https://download.swift.org/swift-sdk-aliases",
            "aliases": {
                "wasi": "wasi.jsonl",
                "static-linux": "static-linux.jsonl"
            },
            "signature": "eyJhbGciOiJFUzI1NiJ9.test.sig"
        }
        """

        let index = try decoder.decode(SwiftSDKAliasIndex.self, from: Data(json.utf8))
        #expect(index.schemaVersion == "1.0")
        #expect(index.remote == "https://download.swift.org/swift-sdk-aliases")
        #expect(index.aliases == ["wasi": "wasi.jsonl", "static-linux": "static-linux.jsonl"])
        #expect(index.signature == "eyJhbGciOiJFUzI1NiJ9.test.sig")

        // Round-trip
        let encoded = try encoder.encode(index)
        let decoded = try decoder.decode(SwiftSDKAliasIndex.self, from: encoded)
        #expect(index == decoded)
    }

    @Test
    func parseAliasIndexMissingOptionalFields() throws {
        let json = """
        {
            "schemaVersion": "1.0",
            "aliases": {
                "wasi": "wasi.jsonl"
            }
        }
        """

        let index = try decoder.decode(SwiftSDKAliasIndex.self, from: Data(json.utf8))
        #expect(index.schemaVersion == "1.0")
        #expect(index.remote == nil)
        #expect(index.aliases.count == 1)
        #expect(index.signature == nil)
    }

    @Test
    func parseAliasIndexUnknownFieldsIgnored() throws {
        let json = """
        {
            "schemaVersion": "1.0",
            "aliases": {},
            "futureField": "some value",
            "anotherFuture": 42
        }
        """

        let index = try decoder.decode(SwiftSDKAliasIndex.self, from: Data(json.utf8))
        #expect(index.schemaVersion == "1.0")
        #expect(index.aliases.isEmpty)
    }

    @Test
    func parseInvalidAliasIndexThrows() throws {
        // Missing required "schemaVersion"
        let missingVersion = """
        {
            "aliases": {"wasi": "wasi.jsonl"}
        }
        """
        #expect(throws: (any Error).self) {
            try decoder.decode(SwiftSDKAliasIndex.self, from: Data(missingVersion.utf8))
        }

        // Missing required "aliases"
        let missingAliases = """
        {
            "schemaVersion": "1.0"
        }
        """
        #expect(throws: (any Error).self) {
            try decoder.decode(SwiftSDKAliasIndex.self, from: Data(missingAliases.utf8))
        }
    }

    @Test
    func parseValidShardEntry() throws {
        let json = """
        { "swiftCompilerTag": "DEVELOPMENT-SNAPSHOT-2025-09-14-a", "checksum": "abc123", "url": "https://swift.org/sdk.tar.gz", "id": "wasi-sdk-1.0", "targetTriple": "wasm32-unknown-wasi" }
        """

        let entry = try decoder.decode(SwiftSDKAliasShardEntry.self, from: Data(json.utf8))
        #expect(entry.swiftCompilerTag == "DEVELOPMENT-SNAPSHOT-2025-09-14-a")
        #expect(entry.checksum == "abc123")
        #expect(entry.url == "https://swift.org/sdk.tar.gz")
        #expect(entry.id == "wasi-sdk-1.0")
        #expect(entry.targetTriple == "wasm32-unknown-wasi")
    }

    @Test
    func parseShardEntryWithoutTargetTriple() throws {
        let json = """
        { "swiftCompilerTag": "swift-6.1-RELEASE", "checksum": "def456", "url": "https://swift.org/sdk.tar.gz", "id": "linux-sdk-1.0" }
        """

        let entry = try decoder.decode(SwiftSDKAliasShardEntry.self, from: Data(json.utf8))
        #expect(entry.swiftCompilerTag == "swift-6.1-RELEASE")
        #expect(entry.targetTriple == nil)
    }
}
