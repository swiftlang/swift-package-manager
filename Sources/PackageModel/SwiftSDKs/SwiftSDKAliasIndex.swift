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

/// Represents the top-level aliases index (`aliases.json`) that maps alias names
/// to shard filenames.
package struct SwiftSDKAliasIndex: Codable, Equatable, Sendable {
    /// The schema version of this index file, using semantic versioning (e.g. "1.0").
    package let schemaVersion: String

    /// The remote URL from which this index was fetched or should be fetched.
    package var remote: String?

    /// A mapping of alias names to their corresponding shard filenames (e.g. "wasi" -> "wasi.jsonl").
    package let aliases: [String: String]

    /// An optional JWS signature for this index.
    package let signature: String?

    package init(
        schemaVersion: String,
        remote: String? = nil,
        aliases: [String: String],
        signature: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.remote = remote
        self.aliases = aliases
        self.signature = signature
    }
}

/// Represents a single entry in a JSONL shard file, mapping a compiler tag to a
/// specific Swift SDK artifact bundle.
package struct SwiftSDKAliasShardEntry: Codable, Equatable, Sendable {
    /// The Swift compiler tag that identifies the toolchain version (e.g.
    /// "DEVELOPMENT-SNAPSHOT-2025-09-14-a", "swift-6.1-RELEASE", "swiftlang-6.0.0.7.6").
    package let swiftCompilerTag: String

    /// The SHA-256 checksum of the artifact bundle archive.
    package let checksum: String

    /// The URL from which the artifact bundle can be downloaded.
    package let url: String

    /// The Swift SDK artifact ID within the bundle.
    package let id: String

    /// The optional target triple for this Swift SDK entry.
    package let targetTriple: String?

    package init(
        swiftCompilerTag: String,
        checksum: String,
        url: String,
        id: String,
        targetTriple: String? = nil
    ) {
        self.swiftCompilerTag = swiftCompilerTag
        self.checksum = checksum
        self.url = url
        self.id = id
        self.targetTriple = targetTriple
    }
}

/// The result of resolving an alias to a specific Swift SDK.
package struct ResolvedSwiftSDKAlias: Equatable, Sendable {
    /// The URL from which the artifact bundle can be downloaded.
    package let url: String

    /// The SHA-256 checksum of the artifact bundle archive.
    package let checksum: String

    /// The Swift SDK artifact ID within the bundle.
    package let id: String

    /// The optional target triple for this Swift SDK.
    package let targetTriple: String?

    package init(url: String, checksum: String, id: String, targetTriple: String? = nil) {
        self.url = url
        self.checksum = checksum
        self.id = id
        self.targetTriple = targetTriple
    }
}
