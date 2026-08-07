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

import Testing
import Foundation
@testable import RegistryExample

@Suite("RegistryStore")
struct RegistryStoreTests {
    private func makeRelease(
        scope: String = "mona",
        name: String = "LinkedList",
        version: String = "1.0.0",
        repositoryURLs: [String]? = nil
    ) throws -> StoredRelease {
        try StoredRelease(
            identifier: PackageIdentifier(scope: scope, name: name),
            version: PackageVersion(version),
            sourceArchive: Data([0x50, 0x4B]),
            sourceArchiveChecksum: "deadbeef",
            manifests: ["": "// swift-tools-version:5.9"],
            metadata: repositoryURLs.map { PackageRelease(repositoryURLs: $0.map { URL(string: $0)! }) },
            metadataRaw: nil,
            publishedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func `publish stores a release and list returns it`() async throws {
        let store = RegistryStore()
        let release = try makeRelease()
        try await store.publish(release)
        let releases = try #require(await store.list(release.identifier))
        #expect(releases.count == 1)
        #expect(releases.first?.version == release.version)
    }

    @Test func `list returns nil for unknown package`() async throws {
        let store = RegistryStore()
        let unknown = try PackageIdentifier(scope: "nobody", name: "Ghost")
        #expect(await store.list(unknown) == nil)
    }

    @Test func `publishing the same version twice throws conflict`() async throws {
        let store = RegistryStore()
        let release = try makeRelease()
        try await store.publish(release)
        await #expect(throws: RegistryStoreError.conflict) {
            try await store.publish(release)
        }
    }

    @Test func `get returns the matching release`() async throws {
        let store = RegistryStore()
        let r1 = try makeRelease(version: "1.0.0")
        let r2 = try makeRelease(version: "1.1.0")
        try await store.publish(r1)
        try await store.publish(r2)
        let got = await store.get(r1.identifier, version: r2.version)
        #expect(got?.version == r2.version)
    }

    @Test func `identifier lookups match metadata.repositoryURLs case-insensitively`() async throws {
        let store = RegistryStore()
        let release = try makeRelease(
            scope: "mona",
            name: "LinkedList",
            repositoryURLs: ["https://github.com/mona/LinkedList"]
        )
        try await store.publish(release)
        let matches = await store.identifiers(matchingURL: "HTTPS://github.com/mona/linkedlist")
        #expect(matches.count == 1)
        #expect(matches.first == release.identifier)
    }

    @Test func `identifier lookups return empty when no match`() async throws {
        let store = RegistryStore()
        let release = try makeRelease(
            repositoryURLs: ["https://github.com/mona/LinkedList"]
        )
        try await store.publish(release)
        let matches = await store.identifiers(matchingURL: "https://example.com/other")
        #expect(matches.isEmpty)
    }
}