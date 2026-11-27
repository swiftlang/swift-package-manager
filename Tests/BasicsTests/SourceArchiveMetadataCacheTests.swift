//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import Testing

struct SourceArchiveMetadataCacheTests {

    private func makeCache() -> (SourceArchiveMetadataCache, InMemoryFileSystem) {
        let fs = InMemoryFileSystem()
        let cachePath = AbsolutePath("/cache/source-archive-metadata")
        let cache = SourceArchiveMetadataCache(fileSystem: fs, cachePath: cachePath)
        return (cache, fs)
    }

    // MARK: - Cache miss

    struct CacheMissCase: CustomTestStringConvertible {
        let label: String
        let lookup: (SourceArchiveMetadataCache) throws -> Any?
        var testDescription: String { label }
    }

    static let cacheMissCases: [CacheMissCase] = [
        CacheMissCase(label: "getMetadata returns nil") { cache in
            try cache.getMetadata(owner: "apple", repo: "swift-nio", sha: "abc123")
        },
        CacheMissCase(label: "getManifest returns nil") { cache in
            try cache.getManifest(owner: "apple", repo: "swift-nio", sha: "abc123", filename: "Package.swift")
        },
    ]

    @Test("Cache miss returns nil", arguments: cacheMissCases)
    func cacheMissReturnsNil(testCase: CacheMissCase) throws {
        let (cache, _) = makeCache()
        let result = try testCase.lookup(cache)
        #expect(result == nil)
    }

    // MARK: - Metadata round-trip

    struct MetadataRoundTripCase: CustomTestStringConvertible {
        let label: String
        let owner: String
        let repo: String
        let sha: String
        let metadata: SourceArchiveMetadata
        var testDescription: String { label }
    }

    static let metadataRoundTripCases: [MetadataRoundTripCase] = [
        MetadataRoundTripCase(
            label: "with submodules",
            owner: "apple", repo: "swift-nio", sha: "abc123",
            metadata: SourceArchiveMetadata(hasSubmodules: true)
        ),
        MetadataRoundTripCase(
            label: "without submodules",
            owner: "apple", repo: "swift-nio", sha: "def456",
            metadata: SourceArchiveMetadata(hasSubmodules: false)
        ),
    ]

    @Test("Metadata round-trips correctly", arguments: metadataRoundTripCases)
    func metadataRoundTrip(testCase: MetadataRoundTripCase) throws {
        let (cache, _) = makeCache()
        try cache.setMetadata(owner: testCase.owner, repo: testCase.repo, sha: testCase.sha, metadata: testCase.metadata)
        let retrieved = try cache.getMetadata(owner: testCase.owner, repo: testCase.repo, sha: testCase.sha)
        #expect(retrieved == testCase.metadata)
    }

    // MARK: - Manifest round-trip

    struct ManifestRoundTripCase: CustomTestStringConvertible {
        let label: String
        let owner: String
        let repo: String
        let sha: String
        let filename: String
        let content: String
        var testDescription: String { label }
    }

    static let manifestRoundTripCases: [ManifestRoundTripCase] = [
        ManifestRoundTripCase(
            label: "standard Package.swift",
            owner: "apple", repo: "swift-nio", sha: "abc123",
            filename: "Package.swift",
            content: """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(name: "MyPackage")
            """
        ),
        ManifestRoundTripCase(
            label: "versioned Package@swift-5.9.swift",
            owner: "apple", repo: "swift-nio", sha: "abc123",
            filename: "Package@swift-5.9.swift",
            content: "// swift-tools-version: 5.9\nimport PackageDescription\n"
        ),
    ]

    @Test("Manifest round-trips correctly", arguments: manifestRoundTripCases)
    func manifestRoundTrip(testCase: ManifestRoundTripCase) throws {
        let (cache, _) = makeCache()
        try cache.setManifest(
            owner: testCase.owner, repo: testCase.repo, sha: testCase.sha,
            filename: testCase.filename, content: testCase.content
        )
        let retrieved = try cache.getManifest(
            owner: testCase.owner, repo: testCase.repo, sha: testCase.sha,
            filename: testCase.filename
        )
        #expect(retrieved == testCase.content)
    }

    @Test("Multiple manifests for same SHA are stored independently")
    func multipleManifestsForSameSHA() throws {
        let (cache, _) = makeCache()
        let mainContent = "// main manifest"
        let variantContent = "// variant manifest"

        try cache.setManifest(
            owner: "apple", repo: "swift-nio", sha: "abc123",
            filename: "Package.swift", content: mainContent
        )
        try cache.setManifest(
            owner: "apple", repo: "swift-nio", sha: "abc123",
            filename: "Package@swift-5.9.swift", content: variantContent
        )

        let main = try cache.getManifest(
            owner: "apple", repo: "swift-nio", sha: "abc123", filename: "Package.swift"
        )
        let variant = try cache.getManifest(
            owner: "apple", repo: "swift-nio", sha: "abc123", filename: "Package@swift-5.9.swift"
        )

        #expect(main == mainContent)
        #expect(variant == variantContent)
    }

    // MARK: - Concurrent access

    @Test("Concurrent access does not crash")
    func concurrentAccessDoesNotCrash() async throws {
        let (cache, _) = makeCache()

        try cache.setMetadata(
            owner: "apple", repo: "swift-nio", sha: "base",
            metadata: SourceArchiveMetadata(hasSubmodules: false)
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let sha = "sha-\(i)"
                    let metadata = SourceArchiveMetadata(hasSubmodules: i % 2 == 0)
                    try cache.setMetadata(owner: "apple", repo: "swift-nio", sha: sha, metadata: metadata)
                    let _ = try cache.getMetadata(owner: "apple", repo: "swift-nio", sha: sha)
                }
                group.addTask {
                    let sha = "sha-\(i)"
                    try cache.setManifest(
                        owner: "apple", repo: "swift-nio", sha: sha,
                        filename: "Package.swift", content: "// content \(i)"
                    )
                    let _ = try cache.getManifest(
                        owner: "apple", repo: "swift-nio", sha: sha,
                        filename: "Package.swift"
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - JSON encoding format

    @Test("Metadata JSON uses snake_case keys")
    func metadataJsonUsesSnakeCaseKeys() throws {
        let (cache, fs) = makeCache()
        let metadata = SourceArchiveMetadata(hasSubmodules: true)

        try cache.setMetadata(owner: "apple", repo: "swift-nio", sha: "abc123", metadata: metadata)

        let jsonPath = AbsolutePath("/cache/source-archive-metadata/apple/swift-nio/abc123/metadata.json")
        let jsonString: String = try fs.readFileContents(jsonPath)

        #expect(jsonString.contains("\"has_submodules\""))
        #expect(!jsonString.contains("\"hasSubmodules\""))
    }
}
